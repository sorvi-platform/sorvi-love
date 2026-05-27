#define SDL_MAIN_USE_CALLBACKS 1
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include "common/config.h"
#include "common/version.h"
#include "common/Module.h"
#include "common/runtime.h"
#include "common/Variant.h"
#include "common/Object.h"
#include "common/Exception.h"

#include "modules/love/love.h"
#include "modules/event/Event.h"
#include "modules/event/sdl/Event.h"
#include "modules/keyboard/sdl/Keyboard.h"
#include "modules/joystick/JoystickModule.h"
#include "modules/touch/sdl/Touch.h"
#include "modules/graphics/Graphics.h"
#include "modules/filesystem/Filesystem.h"
#include "modules/window/Window.h"
#include "modules/audio/Audio.h"
#include "modules/timer/Timer.h"

#include "sensor/sdl/Sensor.h"
#include "joystick/sdl/Joystick.h"
#include "window/sdl/Window.h"

extern "C" {
	#include <lua.h>
	#include <lualib.h>
	#include <lauxlib.h>
}

// Needed for sorvi, in future these will be metadata in the sorvi archive instead
extern const char SDL_SORVI_app_id[] = "org.sorvi.port.love2d";
extern const char SDL_SORVI_app_name[] = "love2d";
extern const char SDL_SORVI_app_version[] = "12.0.0";

enum DoneAction
{
	DONE_QUIT,
	DONE_RESTART,
};

static int love_preload(lua_State *L, lua_CFunction f, const char *name)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");
	lua_pushcfunction(L, f);
	lua_setfield(L, -2, name);
	lua_pop(L, 2);
	return 0;
}

struct State {
    lua_State *lua;
    int boot_return_position;
    love::Variant restart_value;
    int return_value;

    // I'm too zig-pilled for C/C++
    void init(int argc, const char **argv) {
        lua_State *L = luaL_newstate();
        luaL_openlibs(L);

        love_preload(L, luaopen_love_jitsetup, "love.jitsetup");
        lua_getglobal(L, "require");
        lua_pushstring(L, "love.jitsetup");
        lua_call(L, 1, 0);

        // Add love to package.preload for easy requiring.
        love_preload(L, luaopen_love, "love");

        {
            lua_newtable(L);

            if (argc > 0)
            {
                lua_pushstring(L, argv[0]);
                lua_rawseti(L, -2, -2);
            }

            lua_pushstring(L, "embedded boot.lua");
            lua_rawseti(L, -2, -1);

            for (int i = 1; i < argc; i++)
            {
                lua_pushstring(L, argv[i]);
                lua_rawseti(L, -2, i);
            }

            lua_setglobal(L, "arg");
        }

        // require "love"
        lua_getglobal(L, "require");
        lua_pushstring(L, "love");
        lua_call(L, 1, 1); // leave the returned table on the stack.

        // Add love._exe = true.
        // This indicates that we're running the standalone version of love, and not
        // the library version.
        {
            lua_pushboolean(L, 1);
            lua_setfield(L, -2, "_exe");
        }

        love::luax_pushvariant(L, this->restart_value);
        lua_setfield(L, -2, "restart");
        this->restart_value = love::Variant();

        // Pop the love table returned by require "love".
        lua_pop(L, 1);

        // require "love.boot" (preloaded when love was required.)
        lua_getglobal(L, "require");
        lua_pushstring(L, "love.boot");
        lua_call(L, 1, 1);

        // Turn the returned boot function into a coroutine and call it until done.
        lua_newthread(L);
        lua_pushvalue(L, -2);

        this->boot_return_position = lua_gettop(L);
        this->lua = L;
    }

    // true if we should continue iterating, false if not.
    bool iterate() {
        lua_State *L = this->lua;

        int nres;
        if (love::luax_resume(L, 0, &nres) == LUA_YIELD) {
            lua_pop(L, nres);
            return true;
        }

        return false;
    }

    DoneAction close() {
        DoneAction done = DONE_QUIT;
        lua_State *L = this->lua;
        int retidx = this->boot_return_position;

        if (!lua_isnoneornil(L, retidx))
        {
            if (lua_type(L, retidx) == LUA_TSTRING && strcmp(lua_tostring(L, retidx), "restart") == 0)
                done = DONE_RESTART;
            if (lua_isnumber(L, retidx))
                this->return_value = (int) lua_tonumber(L, retidx);

            // Disallow userdata (love objects) from being referenced by the restart
            // value.
            if (retidx < lua_gettop(L))
                this->restart_value = love::luax_checkvariant(L, retidx + 1, false);
        }

        lua_close(L);
        return done;
    }
};

const char *default_arguments[] = {"/sorvi-love", "/core/"};

extern "C" SDL_AppResult SDL_AppInit(void** appstate, int argc, char *argv[]) {
    static State state;
    *appstate = &state;
    
    state.init((sizeof(default_arguments) / sizeof(const char*)), default_arguments);
    // It seems we must iterate once for earlyInit
    if (state.iterate()) return SDL_APP_CONTINUE;
    return SDL_APP_SUCCESS;
}

// SDL reports mouse coordinates in the window coordinate system in OS X, but
// we want them in pixel coordinates (may be different with high-DPI enabled.)
static void windowToDPICoords(love::window::Window *window, double *x, double *y)
{
	if (window)
		window->windowToDPICoords(x, y);
}

static void clampToWindow(love::window::Window *window, double *x, double *y)
{
	if (window)
		window->clampPositionInWindow(x, y);
}

static void normalizedToDPICoords(love::window::Window *window, double *x, double *y)
{
	double w = 1.0, h = 1.0;

	if (window)
	{
		w = window->getWidth();
		h = window->getHeight();
		window->windowToDPICoords(&w, &h);
	}

	if (x)
		*x = ((*x) * w);
	if (y)
		*y = ((*y) * h);
}

// NOTE: Copy-pasted from modules/event/sdl/Event.cpp, don't you love when functions are private :D?
static love::event::Message *convertJoystickEvent(const SDL_Event &e)
{
	auto joymodule = love::Module::getInstance<love::joystick::JoystickModule>(love::Module::M_JOYSTICK);
	if (!joymodule)
		return nullptr;

	love::event::Message *msg = nullptr;

	std::vector<love::Variant> vargs;
	vargs.reserve(4);

	love::Type *joysticktype = &love::joystick::Joystick::type;
	love::joystick::Joystick *stick = nullptr;
	love::joystick::Joystick::Hat hat;
	love::joystick::Joystick::GamepadButton padbutton;
	love::joystick::Joystick::GamepadAxis padaxis;
	const char *txt;

	switch (e.type)
	{
	case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
	case SDL_EVENT_JOYSTICK_BUTTON_UP:
		stick = joymodule->getJoystickFromID(e.jbutton.which);
		if (!stick)
			break;

		vargs.emplace_back(joysticktype, stick);
		vargs.emplace_back((double)(e.jbutton.button+1));
		msg = new love::event::Message((e.type == SDL_EVENT_JOYSTICK_BUTTON_DOWN) ?
						  "joystickpressed" : "joystickreleased",
						  vargs);
		break;
	case SDL_EVENT_JOYSTICK_AXIS_MOTION:
		{
			stick = joymodule->getJoystickFromID(e.jaxis.which);
			if (!stick)
				break;

			vargs.emplace_back(joysticktype, stick);
			vargs.emplace_back((double)(e.jaxis.axis+1));
			float value = love::joystick::Joystick::clampval(e.jaxis.value / 32768.0f);
			vargs.emplace_back((double) value);
			msg = new love::event::Message("joystickaxis", vargs);
		}
		break;
	case SDL_EVENT_JOYSTICK_HAT_MOTION:
		if (!love::joystick::sdl::Joystick::getConstant(e.jhat.value, hat) || !love::joystick::Joystick::getConstant(hat, txt))
			break;

		stick = joymodule->getJoystickFromID(e.jhat.which);
		if (!stick)
			break;

		vargs.emplace_back(joysticktype, stick);
		vargs.emplace_back((double)(e.jhat.hat+1));
		vargs.emplace_back(txt, strlen(txt));
		msg = new love::event::Message("joystickhat", vargs);
		break;
	case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
	case SDL_EVENT_GAMEPAD_BUTTON_UP:
		{
			const auto &b = e.gbutton;
			if (!love::joystick::sdl::Joystick::getConstant((SDL_GamepadButton) b.button, padbutton))
				break;

			if (!love::joystick::Joystick::getConstant(padbutton, txt))
				break;

			stick = joymodule->getJoystickFromID(b.which);
			if (!stick)
				break;

			vargs.emplace_back(joysticktype, stick);
			vargs.emplace_back(txt, strlen(txt));
			msg = new love::event::Message(e.type == SDL_EVENT_GAMEPAD_BUTTON_DOWN ?
							  "gamepadpressed" : "gamepadreleased", vargs);
		}
		break;
	case SDL_EVENT_GAMEPAD_AXIS_MOTION:
		if (love::joystick::sdl::Joystick::getConstant((SDL_GamepadAxis) e.gaxis.axis, padaxis))
		{
			if (!love::joystick::Joystick::getConstant(padaxis, txt))
				break;

			const auto &a = e.gaxis;
			stick = joymodule->getJoystickFromID(a.which);
			if (!stick)
				break;

			vargs.emplace_back(joysticktype, stick);
			vargs.emplace_back(txt, strlen(txt));
			float value = love::joystick::Joystick::clampval(a.value / 32768.0f);
			vargs.emplace_back((double) value);
			msg = new love::event::Message("gamepadaxis", vargs);
		}
		break;
	case SDL_EVENT_JOYSTICK_ADDED:
		// jdevice.which is the joystick device index.
		stick = joymodule->addJoystick(e.jdevice.which);
		if (stick)
		{
			vargs.emplace_back(joysticktype, stick);
			msg = new love::event::Message("joystickadded", vargs);
		}
		break;
	case SDL_EVENT_JOYSTICK_REMOVED:
		// jdevice.which is the joystick instance ID now.
		stick = joymodule->getJoystickFromID(e.jdevice.which);
		if (stick)
		{
			joymodule->removeJoystick(stick);
			vargs.emplace_back(joysticktype, stick);
			msg = new love::event::Message("joystickremoved", vargs);
		}
		break;
#if defined(LOVE_ENABLE_SENSOR)
	case SDL_EVENT_GAMEPAD_SENSOR_UPDATE:
		{
			const auto &sens = e.gsensor;
			stick = joymodule->getJoystickFromID(sens.which);
			if (stick)
			{
				using Sensor = love::sensor::Sensor;

				const char *sensorName;
				Sensor::SensorType sensorType = love::sensor::sdl::Sensor::convert((SDL_SensorType) sens.sensor);
				if (!Sensor::getConstant(sensorType, sensorName))
					sensorName = "unknown";

				vargs.emplace_back(joysticktype, stick);
				vargs.emplace_back(sensorName, strlen(sensorName));
				vargs.emplace_back(sens.data[0]);
				vargs.emplace_back(sens.data[1]);
				vargs.emplace_back(sens.data[2]);
				msg = new love::event::Message("joysticksensorupdated", vargs);
			}
		}
		break;
#endif // defined(LOVE_ENABLE_SENSOR)
	default:
		break;
	}

	return msg;
}

static love::event::Message *convertWindowEvent(const SDL_Event &e, love::window::Window *win)
{
	love::event::Message *msg = nullptr;

	std::vector<love::Variant> vargs;
	vargs.reserve(4);

	love::graphics::Graphics *gfx = nullptr;

	auto event = e.type;

	switch (event)
	{
	case SDL_EVENT_WINDOW_FOCUS_GAINED:
	case SDL_EVENT_WINDOW_FOCUS_LOST:
		vargs.emplace_back(event == SDL_EVENT_WINDOW_FOCUS_GAINED);
		msg = new love::event::Message("focus", vargs);
		break;
	case SDL_EVENT_WINDOW_MOUSE_ENTER:
	case SDL_EVENT_WINDOW_MOUSE_LEAVE:
		vargs.emplace_back(event == SDL_EVENT_WINDOW_MOUSE_ENTER);
		msg = new love::event::Message("mousefocus", vargs);
		break;
	case SDL_EVENT_WINDOW_SHOWN:
	case SDL_EVENT_WINDOW_HIDDEN:
	case SDL_EVENT_WINDOW_MINIMIZED:
	case SDL_EVENT_WINDOW_RESTORED:
#ifdef LOVE_ANDROID
		if (auto audio = love::Module::getInstance<love::audio::Audio>(love::Module::M_AUDIO))
		{
			if (event == SDL_EVENT_WINDOW_MINIMIZED)
				audio->pauseContext();
			else if (event == SDL_EVENT_WINDOW_RESTORED)
				audio->resumeContext();
		}
#endif
		// WINDOW_RESTORED can also happen when going from maximized -> unmaximized,
		// but there isn't a nice way to avoid sending our event in that situation.
		vargs.emplace_back(event == SDL_EVENT_WINDOW_SHOWN || event == SDL_EVENT_WINDOW_RESTORED);
		msg = new love::event::Message("visible", vargs);
		break;
	case SDL_EVENT_WINDOW_EXPOSED:
		msg = new love::event::Message("exposed");
		break;
	case SDL_EVENT_WINDOW_OCCLUDED:
		msg = new love::event::Message("occluded");
		break;
	case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
		{
			double width = e.window.data1;
			double height = e.window.data2;

			gfx = love::Module::getInstance<love::graphics::Graphics>(love::Module::M_GRAPHICS);
			if (win)
				win->onSizeChanged(e.window.data1, e.window.data2);

			// The size values in the Window aren't necessarily the same as the
			// graphics size, which is what we want to output.
			if (gfx)
			{
				width = gfx->getWidth();
				height = gfx->getHeight();
			}
			else if (win)
			{
				width = win->getWidth();
				height = win->getHeight();
				windowToDPICoords(win, &width, &height);
			}

			vargs.emplace_back(width);
			vargs.emplace_back(height);
			msg = new love::event::Message("resize", vargs);
		}
		break;
	}

	return msg;
}

static love::event::Message *convert(const SDL_Event &e)
{
	love::event::Message *msg = nullptr;

	std::vector<love::Variant> vargs;
	vargs.reserve(4);

	love::filesystem::Filesystem *filesystem = nullptr;
	love::sensor::Sensor *sensorInstance = nullptr;
	love::window::Window *win = love::Module::getInstance<love::window::Window>(love::Module::M_WINDOW);

	love::keyboard::Keyboard::Key key = love::keyboard::Keyboard::KEY_UNKNOWN;
	love::keyboard::Keyboard::Scancode scancode = love::keyboard::Keyboard::SCANCODE_UNKNOWN;

	const char *txt;
	const char *txt2;

	love::touch::sdl::Touch *touchmodule = nullptr;
	love::touch::Touch::TouchInfo touchinfo = {};

	if (win)
	{
		// Dubious cast, but it's not like having an SDL event backend
		// with a non-SDL window backend will be a thing.
		auto sdlwin = dynamic_cast<love::window::sdl::Window *>(win);
		if (sdlwin != nullptr)
			sdlwin->handleSDLEvent(e);
	}

	switch (e.type)
	{
	case SDL_EVENT_KEY_DOWN:
		if (e.key.repeat)
		{
			auto kb = love::Module::getInstance<love::keyboard::Keyboard>(love::Module::M_KEYBOARD);
			if (kb && !kb->hasKeyRepeat())
				break;
		}

		love::keyboard::sdl::Keyboard::getConstant(e.key.key, key);
		if (!love::keyboard::Keyboard::getConstant(key, txt))
			txt = "unknown";

		love::keyboard::sdl::Keyboard::getConstant(e.key.scancode, scancode);
		if (!love::keyboard::Keyboard::getConstant(scancode, txt2))
			txt2 = "unknown";

		vargs.emplace_back(txt, strlen(txt));
		vargs.emplace_back(txt2, strlen(txt2));
		vargs.emplace_back(e.key.repeat != 0);
		msg = new love::event::Message("keypressed", vargs);
		break;
	case SDL_EVENT_KEY_UP:
		love::keyboard::sdl::Keyboard::getConstant(e.key.key, key);
		if (!love::keyboard::Keyboard::getConstant(key, txt))
			txt = "unknown";

		love::keyboard::sdl::Keyboard::getConstant(e.key.scancode, scancode);
		if (!love::keyboard::Keyboard::getConstant(scancode, txt2))
			txt2 = "unknown";

		vargs.emplace_back(txt, strlen(txt));
		vargs.emplace_back(txt2, strlen(txt2));
		msg = new love::event::Message("keyreleased", vargs);
		break;
	case SDL_EVENT_TEXT_INPUT:
		txt = e.text.text;
		vargs.emplace_back(txt, strlen(txt));
		msg = new love::event::Message("textinput", vargs);
		break;
	case SDL_EVENT_TEXT_EDITING:
		txt = e.edit.text;
		vargs.emplace_back(txt, strlen(txt));
		vargs.emplace_back((double) e.edit.start);
		vargs.emplace_back((double) e.edit.length);
		msg = new love::event::Message("textedited", vargs);
		break;
	case SDL_EVENT_MOUSE_MOTION:
		{
			double x = (double) e.motion.x;
			double y = (double) e.motion.y;
			double xrel = (double) e.motion.xrel;
			double yrel = (double) e.motion.yrel;

			// SDL reports mouse coordinates outside the window bounds when click-and-
			// dragging. For compatibility we clamp instead since user code may not be
			// able to handle out-of-bounds coordinates. SDL has a hint to turn off
			// auto capture, but it doesn't report the mouse's position at the edge of
			// the window if the mouse moves fast enough when it's off.
			clampToWindow(win, &x, &y);
			windowToDPICoords(win, &x, &y);
			windowToDPICoords(win, &xrel, &yrel);

			vargs.emplace_back(x);
			vargs.emplace_back(y);
			vargs.emplace_back(xrel);
			vargs.emplace_back(yrel);
			vargs.emplace_back(e.motion.which == SDL_TOUCH_MOUSEID);
			msg = new love::event::Message("mousemoved", vargs);
		}
		break;
	case SDL_EVENT_MOUSE_BUTTON_DOWN:
	case SDL_EVENT_MOUSE_BUTTON_UP:
		{
			// SDL uses button 3 for the right mouse button, but we use button 2
			int button = e.button.button;
			switch (button)
			{
			case SDL_BUTTON_RIGHT:
				button = 2;
				break;
			case SDL_BUTTON_MIDDLE:
				button = 3;
				break;
			}

			double px = (double) e.button.x;
			double py = (double) e.button.y;

			clampToWindow(win, &px, &py);
			windowToDPICoords(win, &px, &py);

			vargs.emplace_back(px);
			vargs.emplace_back(py);
			vargs.emplace_back((double) button);
			vargs.emplace_back(e.button.which == SDL_TOUCH_MOUSEID);
			vargs.emplace_back((double) e.button.clicks);

			bool down = e.type == SDL_EVENT_MOUSE_BUTTON_DOWN;
			msg = new love::event::Message(down ? "mousepressed" : "mousereleased", vargs);
		}
		break;
	case SDL_EVENT_MOUSE_WHEEL:
		vargs.emplace_back((double) e.wheel.x);
		vargs.emplace_back((double) e.wheel.y);

		txt = e.wheel.direction == SDL_MOUSEWHEEL_FLIPPED ? "flipped" : "standard";
		vargs.emplace_back(txt, strlen(txt));

		msg = new love::event::Message("wheelmoved", vargs);
		break;
	case SDL_EVENT_FINGER_DOWN:
	case SDL_EVENT_FINGER_UP:
	case SDL_EVENT_FINGER_MOTION:
		touchinfo.id = (love::int64)e.tfinger.fingerID;
		touchinfo.x = e.tfinger.x;
		touchinfo.y = e.tfinger.y;
		touchinfo.dx = e.tfinger.dx;
		touchinfo.dy = e.tfinger.dy;
		touchinfo.pressure = e.tfinger.pressure;
		touchinfo.deviceType = love::touch::sdl::Touch::getDeviceType(SDL_GetTouchDeviceType(e.tfinger.touchID));
		touchinfo.mouse = e.tfinger.touchID == SDL_MOUSE_TOUCHID;

		// SDL's coords are normalized to [0, 1], but we want screen coords for direct touches.
		if (touchinfo.deviceType == love::touch::Touch::DEVICE_TOUCHSCREEN)
		{
			normalizedToDPICoords(win, &touchinfo.x, &touchinfo.y);
			normalizedToDPICoords(win, &touchinfo.dx, &touchinfo.dy);
		}

		// We need to update the love.touch.sdl internal state from here.
		touchmodule = (love::touch::sdl::Touch *) love::Module::getInstance("love.touch.sdl");
		if (touchmodule)
			touchmodule->onEvent(e.type, touchinfo);

		if (!love::touch::Touch::getConstant(touchinfo.deviceType, txt))
			txt = "unknown";

		// This is a bit hackish and we lose the higher 32 bits of the id on
		// 32-bit systems, but SDL only ever gives id's that at most use as many
		// bits as can fit in a pointer (for now.)
		// We use lightuserdata instead of a lua_Number (double) because doubles
		// can't represent all possible id values on 64-bit systems.
		vargs.emplace_back((void *)(intptr_t)touchinfo.id);
		vargs.emplace_back(touchinfo.x);
		vargs.emplace_back(touchinfo.y);
		vargs.emplace_back(touchinfo.dx);
		vargs.emplace_back(touchinfo.dy);
		vargs.emplace_back(touchinfo.pressure);
		vargs.emplace_back(txt, strlen(txt));
		vargs.emplace_back(touchinfo.mouse);

		if (e.type == SDL_EVENT_FINGER_DOWN)
			txt = "touchpressed";
		else if (e.type == SDL_EVENT_FINGER_UP || e.type == SDL_EVENT_FINGER_CANCELED)
			txt = "touchreleased";
		else
			txt = "touchmoved";
		msg = new love::event::Message(txt, vargs);
		break;
	case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
	case SDL_EVENT_JOYSTICK_BUTTON_UP:
	case SDL_EVENT_JOYSTICK_AXIS_MOTION:
	case SDL_EVENT_JOYSTICK_HAT_MOTION:
	case SDL_EVENT_JOYSTICK_ADDED:
	case SDL_EVENT_JOYSTICK_REMOVED:
	case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
	case SDL_EVENT_GAMEPAD_BUTTON_UP:
	case SDL_EVENT_GAMEPAD_AXIS_MOTION:
	case SDL_EVENT_GAMEPAD_SENSOR_UPDATE:
		msg = convertJoystickEvent(e);
		break;
	case SDL_EVENT_WINDOW_FOCUS_GAINED:
	case SDL_EVENT_WINDOW_FOCUS_LOST:
	case SDL_EVENT_WINDOW_MOUSE_ENTER:
	case SDL_EVENT_WINDOW_MOUSE_LEAVE:
	case SDL_EVENT_WINDOW_SHOWN:
	case SDL_EVENT_WINDOW_HIDDEN:
	case SDL_EVENT_WINDOW_RESIZED:
	case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
	case SDL_EVENT_WINDOW_MINIMIZED:
	case SDL_EVENT_WINDOW_RESTORED:
	case SDL_EVENT_WINDOW_EXPOSED:
	case SDL_EVENT_WINDOW_OCCLUDED:
		msg = convertWindowEvent(e, win);
		break;
	case SDL_EVENT_DISPLAY_ORIENTATION:
		{
			auto orientation = love::window::Window::ORIENTATION_UNKNOWN;
			switch ((SDL_DisplayOrientation) e.display.data1)
			{
			case SDL_ORIENTATION_UNKNOWN:
			default:
				orientation = love::window::Window::ORIENTATION_UNKNOWN;
				break;
			case SDL_ORIENTATION_LANDSCAPE:
				orientation = love::window::Window::ORIENTATION_LANDSCAPE;
				break;
			case SDL_ORIENTATION_LANDSCAPE_FLIPPED:
				orientation = love::window::Window::ORIENTATION_LANDSCAPE_FLIPPED;
				break;
			case SDL_ORIENTATION_PORTRAIT:
				orientation = love::window::Window::ORIENTATION_PORTRAIT;
				break;
			case SDL_ORIENTATION_PORTRAIT_FLIPPED:
				orientation = love::window::Window::ORIENTATION_PORTRAIT_FLIPPED;
				break;
			}

			if (!love::window::Window::getConstant(orientation, txt))
				txt = "unknown";

			int count = 0;
			int displayindex = 0;
			SDL_DisplayID *displays = SDL_GetDisplays(&count);
			for (int i = 0; i < count; i++)
			{
				if (displays[i] == e.display.displayID)
				{
					displayindex = i;
					break;
				}
			}
			SDL_free(displays);
			vargs.emplace_back((double)(displayindex + 1));
			vargs.emplace_back(txt, strlen(txt));

			msg = new love::event::Message("displayrotated", vargs);
		}
		break;
	case SDL_EVENT_DROP_BEGIN:
		msg = new love::event::Message("dropbegan", vargs);
		break;
	case SDL_EVENT_DROP_COMPLETE:
		{
			double x = e.drop.x;
			double y = e.drop.y;
			windowToDPICoords(win, &x, &y);
			vargs.emplace_back(x);
			vargs.emplace_back(y);
			msg = new love::event::Message("dropcompleted", vargs);
		}
		break;
	case SDL_EVENT_DROP_POSITION:
		{
			double x = e.drop.x;
			double y = e.drop.y;
			windowToDPICoords(win, &x, &y);
			vargs.emplace_back(x);
			vargs.emplace_back(y);
			msg = new love::event::Message("dropmoved", vargs);
		}
		break;
	case SDL_EVENT_DROP_FILE:
		filesystem = love::Module::getInstance<love::filesystem::Filesystem>(love::Module::M_FILESYSTEM);
		if (filesystem != nullptr)
		{
			const char *filepath = e.drop.data;
			// Allow mounting any dropped path, so zips or dirs can be mounted.
			filesystem->allowMountingForPath(filepath);

			double x = e.drop.x;
			double y = e.drop.y;
			windowToDPICoords(win, &x, &y);

			if (filesystem->isRealDirectory(filepath))
			{
				vargs.emplace_back(filepath, strlen(filepath));
				vargs.emplace_back(x);
				vargs.emplace_back(y);
				msg = new love::event::Message("directorydropped", vargs);
			}
			else
			{
				auto *file = filesystem->openNativeFile(filepath, love::filesystem::File::MODE_CLOSED);
				vargs.emplace_back(&love::filesystem::File::type, file);
				vargs.emplace_back(x);
				vargs.emplace_back(y);
				msg = new love::event::Message("filedropped", vargs);
				file->release();
			}
		}
		break;
	case SDL_EVENT_QUIT:
	case SDL_EVENT_TERMINATING:
		msg = new love::event::Message("quit");
		break;
	case SDL_EVENT_LOW_MEMORY:
		msg = new love::event::Message("lowmemory");
		break;
	case SDL_EVENT_LOCALE_CHANGED:
		msg = new love::event::Message("localechanged");
		break;
	case SDL_EVENT_SYSTEM_THEME_CHANGED:
		msg = new love::event::Message("themechanged");
		break;
	case SDL_EVENT_SENSOR_UPDATE:
		sensorInstance = love::Module::getInstance<love::sensor::Sensor>(love::Module::M_SENSOR);
		if (sensorInstance)
		{
			std::vector<void*> sensors = sensorInstance->getHandles();

			for (void *s: sensors)
			{
				SDL_Sensor *sensor = (SDL_Sensor *) s;
				SDL_SensorID id = SDL_GetSensorID(sensor);

				if (e.sensor.which == id)
				{
					// Found sensor
					const char *sensorType;
					auto sdltype = SDL_GetSensorType(sensor);
					if (!love::sensor::Sensor::getConstant(love::sensor::sdl::Sensor::convert(sdltype), sensorType))
						sensorType = "unknown";

					vargs.emplace_back(sensorType, strlen(sensorType));
					// Both accelerometer and gyroscope only pass up to 3 values.
					// https://github.com/libsdl-org/SDL/blob/SDL2/include/SDL_sensor.h#L81-L127
					vargs.emplace_back(e.sensor.data[0]);
					vargs.emplace_back(e.sensor.data[1]);
					vargs.emplace_back(e.sensor.data[2]);
					msg = new love::event::Message("sensorupdated", vargs);

					break;
				}
			}
		}
		break;
	default:
		break;
	}

	return msg;
}

extern "C" SDL_AppResult SDL_AppEvent(void* appstate, SDL_Event *event) {
    State* state = static_cast<State*>(appstate);
    auto event_instance = static_cast<love::event::sdl::Event*>(love::Module::getInstance<love::event::Event>(love::Module::M_EVENT));
    love::StrongRef<love::event::Message> msg(convert(*event), love::Acquire::NORETAIN);
    if (msg) event_instance->push(msg);
    return SDL_APP_CONTINUE;
}

extern "C" SDL_AppResult SDL_AppIterate(void* appstate) {
    State* state = static_cast<State*>(appstate);
    if (state->iterate()) return SDL_APP_CONTINUE;
    
    switch (state->close()) {
        case DONE_RESTART: {
            state->init((sizeof(default_arguments) / sizeof(const char*)), default_arguments);
            return SDL_APP_CONTINUE;
        }
        case DONE_QUIT: return SDL_APP_SUCCESS;
    }
}

extern "C" void SDL_AppQuit(void* appstate, SDL_AppResult result) {}
