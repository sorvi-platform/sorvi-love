const std = @import("std");
const Build = std.Build;
const sorvi = @import("sorvi");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const starget = sorvi.resolveSorviTarget(b, target.query);
    const optimize = b.standardOptimizeOption(.{});

    // fixup hack until sorvi repo becomes public
    // set this to true whenever these deps update
    // and then back to false once symlinks are updated
    if (false) {
        const zon = @import("build.zig.zon");
        inline for (.{ "sorvi_SDL3", "sorvi_physfs" }) |name| {
            const dep = @field(zon.dependencies, name);
            const path = b.build_root.join(b.allocator, &.{ "zig-pkg", dep.hash }) catch @panic("OOM");
            const dir = std.Io.Dir.cwd().openDir(b.graph.io, path, .{}) catch unreachable;
            dir.symLink(b.graph.io, b.pathFromRoot("../sorvi"), "sorvi", .{ .is_directory = true }) catch {};
        }
        return;
    }

    const sorvi_dep = b.dependency("sorvi", .{
        .target = target,
        .optimize = optimize,
    });
    const frontend = sorvi_dep.artifact("sorvi-frontend");
    const sdl3_dep = b.dependency("sorvi_SDL3", .{
        .target = starget,
        .optimize = optimize,
    });
    const al_dep = b.dependency("openal", .{
        .target = starget,
        .optimize = optimize, 
        .backend = .sdl3,
    });
    const freetype_dep = b.dependency("freetype", .{
        .target = starget,
        .optimize = optimize, 
    });
    const harfbuzz_dep = b.dependency("harfbuzz", .{
        .target = starget,
        .optimize = optimize, 
    });
    const modplug_dep = b.dependency("modplug", .{
        .target = starget,
        .optimize = optimize, 
    });
    const theora_dep = b.dependency("theora", .{
        .target = starget,
        .optimize = optimize, 
    });
    const vorbis_dep = b.dependency("libvorbis", .{
        .target = starget,
        .optimize = optimize, 
    });
    const zlib_dep = b.dependency("zlib", .{
        .target = starget,
        .optimize = optimize, 
    });
    const lua_dep = b.dependency("lua", .{
        .target = starget,
        .optimize = optimize, 
    });

    const upstream = b.dependency("love2d", .{});

    const lua_mod = b.createModule(.{
        .target = starget,
        .optimize = optimize,
        .link_libc = true,
        .sanitize_c = .off,
    });
    
    lua_mod.addCSourceFiles(.{
        .root = lua_dep.path("src/"),
        .files = lua51_srcs,
        .flags = &.{},
    });

    const lua51 = b.addLibrary(.{
        .name = "lua",
        .root_module = lua_mod,
    });
    lua51.installHeadersDirectory(lua_dep.path("src"), "", .{ .include_extensions = &.{".h"}});

    const box2d_mod = b.createModule(.{
        .target = starget,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .sanitize_c = .off,
    });
    box2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/box2d/"),
        .files = box2d_srcs,
        .flags = &.{},
    });
    box2d_mod.addIncludePath(upstream.path("src/libraries/"));
    box2d_mod.addIncludePath(upstream.path("src/"));

    const box2d = b.addLibrary(.{
        .name = "box2d",
        .root_module = box2d_mod,
    });
    box2d.installHeadersDirectory(upstream.path("src/libraries/box2d/"), "box2d/", .{ .include_extensions = &.{".h"}});

    const glslang_mod = b.addModule("glslang", .{
        .target = starget,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .sanitize_c = .off,
    });
    glslang_mod.addIncludePath(upstream.path("src/libraries/"));
    glslang_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/glslang"),
        .files = glslang_srcs,
    });

    const glslang = b.addLibrary(.{
        .name = "glslang",
        .root_module = glslang_mod,
    });

    const physfs_mod = b.addModule("physfs", .{
        .target = starget,
        .optimize = optimize,
        .link_libc = true,
        .sanitize_c = .off,
        .root_source_file = b.path("src/physfs_platform_sorvi.zig"),
    });
    {
        var files = b.addWriteFiles();
        _ = files.addCopyDirectory(upstream.path("src/libraries/physfs/"), "", .{});
        _ = files.addCopyDirectory(b.path("src"), "", .{});
        physfs_mod.addCSourceFiles(.{
            .root = files.getDirectory(),
            .files = physfs_srcs,
        });
    }

    const physfs = b.addLibrary(.{
        .name = "physfs",
        .root_module = physfs_mod,
    });

    const l2d_mod = b.createModule(.{
        .target = starget,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .sanitize_c = .off,
    });

    l2d_mod.addIncludePath(b.path("src/include/"));
    l2d_mod.addIncludePath(upstream.path("src/"));
    l2d_mod.addIncludePath(upstream.path("src/libraries/"));
    l2d_mod.addIncludePath(upstream.path("src/modules/"));
    l2d_mod.addCSourceFile(.{ .file = b.path("src/sorvi-love.cpp") });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/"),
        .files = liblove_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/common"),
        .files = common_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/audio"),
        .files = audio_common_srcs ++ audio_null_srcs ++ audio_al_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/data"),
        .files = data_common_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/event"),
        .files = event_common_srcs ++ event_sdl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/filesystem"),
        .files = fs_common_srcs ++ fs_physfs_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/font"),
        .files = font_common_srcs ++ font_freetype_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/graphics"),
        .files = graphics_common_srcs ++ graphics_opengl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/image"),
        .files = image_common_srcs ++ image_magpie_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/joystick"),
        .files = joystick_common_srcs ++ joystick_sdl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/keyboard"),
        .files = keyboard_common_srcs ++ keyboard_sdl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/math"),
        .files = math_common_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/mouse"),
        .files = mouse_common_srcs ++ mouse_sdl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/physics"),
        .files = physics_common_srcs ++ physics_box2d_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/sound"),
        .files = sound_common_srcs ++ sound_lullaby_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/sensor"),
        .files = sensor_common_srcs ++ sensor_sdl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/system"),
        .files = system_common_srcs ++ system_sdl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/thread"),
        .files = thread_common_srcs ++ thread_sdl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/timer"),
        .files = timer_common_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/touch"),
        .files = touch_common_srcs ++ touch_sdl_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/video"),
        .files = video_common_srcs ++ video_theora_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/modules/window"),
        .files = window_common_srcs ++ window_sdl_srcs,
    });

    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/lua53"),
        .files = lua53_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/glad"),
        .files = glad_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/lz4"),
        .files = lz4_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/ddsparse"),
        .files = ddsparse_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/lodepng"),
        .files = lodepng_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/Wuff"),
        .files = wuff_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/xxHash"),
        .files = xxhash_srcs,
    });
    l2d_mod.addCSourceFiles(.{
        .root = upstream.path("src/libraries/noise1234"),
        .files = noise1234_srcs,
    });
    l2d_mod.addCMacro("HAVE_CONFIG_H", "1");

    const sdl3 = sdl3_dep.artifact("SDL3");
    l2d_mod.linkLibrary(sdl3);
    const al = al_dep.artifact("al");
    al.root_module.linkLibrary(sdl3);
    l2d_mod.addIncludePath(al.installed_headers.getLast().getSource().path(b, "AL"));
    l2d_mod.linkLibrary(al);
    l2d_mod.linkLibrary(freetype_dep.artifact("freetype"));
    l2d_mod.linkLibrary(harfbuzz_dep.artifact("harfbuzz"));
    l2d_mod.linkLibrary(modplug_dep.artifact("modplug"));
    l2d_mod.linkLibrary(theora_dep.artifact("theora"));
    l2d_mod.linkLibrary(vorbis_dep.artifact("vorbis"));
    l2d_mod.linkLibrary(vorbis_dep.artifact("ogg"));
    l2d_mod.linkLibrary(zlib_dep.artifact("z"));
    l2d_mod.linkLibrary(lua51);
    l2d_mod.linkLibrary(box2d);
    l2d_mod.linkLibrary(glslang);
    l2d_mod.linkLibrary(physfs);

    const assets = b.addWriteFiles();
    _ = assets.addCopyDirectory(b.path("test"), "", .{});
    const love2d = sorvi.addSorviCore(b, .{
        .name = "love2d",
        .root_module = l2d_mod,
        .assets = assets,
    });

    love2d.fixup(b);

    const step = b.step("run", "Run love2d in a reference frontend");
    step.dependOn(&sorvi.addRunSorviCore(b, frontend, love2d).step);
}

const lua51_srcs: []const []const u8 = &.{
    "lapi.c",
    "lauxlib.c",
    "lbaselib.c",
    "lcode.c",
    "ldblib.c",
    "ldebug.c",
    "ldo.c",
    "ldump.c",
    "lfunc.c",
    "lgc.c",
    "linit.c",
    "liolib.c",
    "llex.c",
    "lmathlib.c",
    "lmem.c",
    "loadlib.c",
    "lobject.c",
    "lopcodes.c",
    "loslib.c",
    "lparser.c",
    "lstate.c",
    "lstring.c",
    "lstrlib.c",
    "ltable.c",
    "ltablib.c",
    "ltm.c",
    "lundump.c",
    "lvm.c",
    "lzio.c",
    "print.c",
};

const box2d_srcs: []const []const u8 = &.{
    "collision/b2_broad_phase.cpp",
    "collision/b2_chain_shape.cpp",
    "collision/b2_circle_shape.cpp",
    "collision/b2_collide_circle.cpp",
    "collision/b2_collide_edge.cpp",
    "collision/b2_collide_polygon.cpp",
    "collision/b2_collision.cpp",
    "collision/b2_distance.cpp",
    "collision/b2_dynamic_tree.cpp",
    "collision/b2_edge_shape.cpp",
    "collision/b2_polygon_shape.cpp",
    "collision/b2_time_of_impact.cpp",
    "common/b2_block_allocator.cpp",
    "common/b2_draw.cpp",
    "common/b2_math.cpp",
    "common/b2_settings.cpp",
    "common/b2_stack_allocator.cpp",
    "common/b2_timer.cpp",
    "dynamics/b2_body.cpp",
    "dynamics/b2_chain_circle_contact.cpp",
    "dynamics/b2_chain_polygon_contact.cpp",
    "dynamics/b2_circle_contact.cpp",
    "dynamics/b2_contact.cpp",
    "dynamics/b2_contact_manager.cpp",
    "dynamics/b2_contact_solver.cpp",
    "dynamics/b2_distance_joint.cpp",
    "dynamics/b2_edge_circle_contact.cpp",
    "dynamics/b2_edge_polygon_contact.cpp",
    "dynamics/b2_fixture.cpp",
    "dynamics/b2_friction_joint.cpp",
    "dynamics/b2_gear_joint.cpp",
    "dynamics/b2_island.cpp",
    "dynamics/b2_joint.cpp",
    "dynamics/b2_motor_joint.cpp",
    "dynamics/b2_mouse_joint.cpp",
    "dynamics/b2_polygon_circle_contact.cpp",
    "dynamics/b2_polygon_contact.cpp",
    "dynamics/b2_prismatic_joint.cpp",
    "dynamics/b2_pulley_joint.cpp",
    "dynamics/b2_revolute_joint.cpp",
    "dynamics/b2_weld_joint.cpp",
    "dynamics/b2_wheel_joint.cpp",
    "dynamics/b2_world.cpp",
    "dynamics/b2_world_callbacks.cpp",
    "rope/b2_rope.cpp",
};

const ddsparse_srcs: []const []const u8 = &.{ "ddsparse.cpp" };
const glad_srcs: []const []const u8 = &.{ "glad.cpp" };
const lz4_srcs: []const []const u8 = &.{ "lz4.c", "lz4hc.c" };
const lua53_srcs: []const []const u8 = &.{ "lstrlib.c", "lutf8lib.c" };
const lodepng_srcs: []const []const u8 = &.{ "lodepng.cpp" };
const wuff_srcs: []const []const u8 = &.{ "wuff.c", "wuff_convert.c", "wuff_internal.c", "wuff_memory.c" };
const xxhash_srcs: []const []const u8 = &.{ "xxhash.c" };
const noise1234_srcs: []const []const u8 = &.{ "noise1234.cpp", "simplexnoise1234.cpp" };
const glslang_srcs: []const []const u8 = &.{
    "glslang/GenericCodeGen/CodeGen.cpp",
    "glslang/GenericCodeGen/Link.cpp",
    "glslang/MachineIndependent/preprocessor/Pp.cpp",
    "glslang/MachineIndependent/preprocessor/PpAtom.cpp",
    "glslang/MachineIndependent/preprocessor/PpContext.cpp",
    "glslang/MachineIndependent/preprocessor/PpScanner.cpp",
    "glslang/MachineIndependent/preprocessor/PpTokens.cpp",
    "glslang/MachineIndependent/attribute.cpp",
    "glslang/MachineIndependent/Constant.cpp",
    "glslang/MachineIndependent/glslang_tab.cpp",
    "glslang/MachineIndependent/InfoSink.cpp",
    "glslang/MachineIndependent/Initialize.cpp",
    "glslang/MachineIndependent/Intermediate.cpp",
    "glslang/MachineIndependent/intermOut.cpp",
    "glslang/MachineIndependent/IntermTraverse.cpp",
    "glslang/MachineIndependent/iomapper.cpp",
    "glslang/MachineIndependent/limits.cpp",
    "glslang/MachineIndependent/linkValidate.cpp",
    "glslang/MachineIndependent/parseConst.cpp",
    "glslang/MachineIndependent/ParseContextBase.cpp",
    "glslang/MachineIndependent/ParseHelper.cpp",
    "glslang/MachineIndependent/PoolAlloc.cpp",
    "glslang/MachineIndependent/propagateNoContraction.cpp",
    "glslang/MachineIndependent/reflection.cpp",
    "glslang/MachineIndependent/RemoveTree.cpp",
    "glslang/MachineIndependent/Scan.cpp",
    "glslang/MachineIndependent/ShaderLang.cpp",
    "glslang/MachineIndependent/SpirvIntrinsics.cpp",
    "glslang/MachineIndependent/SymbolTable.cpp",
    "glslang/MachineIndependent/Versions.cpp",
    "glslang/ResourceLimits/ResourceLimits.cpp",
    "SPIRV/disassemble.cpp",
    "SPIRV/doc.cpp",
    "SPIRV/GlslangToSpv.cpp",
    "SPIRV/InReadableOrder.cpp",
    "SPIRV/Logger.cpp",
    "SPIRV/SpvBuilder.cpp",
    "SPIRV/SpvPostProcess.cpp",
    "SPIRV/SPVRemapper.cpp",
    "SPIRV/SpvTools.cpp",
};

const physfs_srcs: []const []const u8 = &.{
    "physfs.c",
    "physfs_archiver_7z.c",
    "physfs_archiver_dir.c",
    "physfs_archiver_grp.c",
    "physfs_archiver_hog.c",
    "physfs_archiver_iso9660.c",
    "physfs_archiver_mvl.c",
    "physfs_archiver_qpak.c",
    "physfs_archiver_slb.c",
    "physfs_archiver_unpacked.c",
    "physfs_archiver_vdf.c",
    "physfs_archiver_wad.c",
    "physfs_archiver_zip.c",
    "physfs_byteorder.c",
    "physfs_platform_posix.c",
    "physfs_unicode.c",
};

const liblove_srcs: []const []const u8 = &.{
    "modules/love/love.cpp",
};

const common_srcs: []const []const u8 = &.{
    "android.cpp",
    "b64.cpp",
    "Data.cpp",
    "delay.cpp",
    "deprecation.cpp",
    "Exception.cpp",
    "floattypes.cpp",
    "Matrix.cpp",
    "memory.cpp",
    "Module.cpp",
    "Object.cpp",
    "pixelformat.cpp",
    "Reference.cpp",
    "runtime.cpp",
    "Stream.cpp",
    "StringMap.cpp",
    "types.cpp",
    "utf8.cpp",
    "Variant.cpp",
};

const audio_common_srcs: []const []const u8 = &.{
    "Audio.cpp",
    "Source.cpp",
    "RecordingDevice.cpp",
    "Filter.cpp",
    "Effect.cpp",
    "wrap_Audio.cpp",
    "wrap_Source.cpp",
    "wrap_RecordingDevice.cpp",
};

const audio_null_srcs: []const []const u8 = &.{
    "null/Audio.cpp",
    "null/Source.cpp",
    "null/RecordingDevice.cpp",
};

const audio_al_srcs: []const []const u8 = &.{
    "openal/Audio.cpp",
    "openal/Pool.cpp",
    "openal/Source.cpp",
    "openal/RecordingDevice.cpp",
    "openal/Filter.cpp",
    "openal/Effect.cpp",
};

const data_common_srcs: []const []const u8 = &.{
    "ByteData.cpp",
    "CompressedData.cpp",
    "Compressor.cpp",
    "DataModule.cpp",
    "DataStream.cpp",
    "DataView.cpp",
    "HashFunction.cpp",
    "wrap_ByteData.cpp",
    "wrap_CompressedData.cpp",
    "wrap_Data.cpp",
    "wrap_DataModule.cpp",
    "wrap_DataView.cpp",
};

const event_common_srcs: []const []const u8 = &.{
    "Event.cpp",
    "wrap_Event.cpp",
};

const event_sdl_srcs: []const []const u8 = &.{
    "sdl/Event.cpp",
};

const fs_common_srcs: []const []const u8 = &.{
    "File.cpp",
    "FileData.cpp",
    "Filesystem.cpp",
    "NativeFile.cpp",
    "wrap_File.cpp",
    "wrap_FileData.cpp",
    "wrap_Filesystem.cpp",
    "wrap_NativeFile.cpp",
};

const fs_physfs_srcs: []const []const u8 = &.{
    "physfs/File.cpp",
    "physfs/Filesystem.cpp",
    "physfs/PhysfsIo.cpp",
};

const font_common_srcs: []const []const u8 = &.{
    "BMFontRasterizer.cpp",
    "Font.cpp",
    "GenericShaper.cpp",
    "GlyphData.cpp",
    "ImageRasterizer.cpp",
    "Rasterizer.cpp",
    "TextShaper.cpp",
    "TrueTypeRasterizer.cpp",
    "wrap_Font.cpp",
    "wrap_GlyphData.cpp",
    "wrap_Rasterizer.cpp",
};

const font_freetype_srcs: []const []const u8 = &.{
    "freetype/Font.cpp",
    "freetype/HarfbuzzShaper.cpp",
    "freetype/TrueTypeRasterizer.cpp",
};

const graphics_common_srcs: []const []const u8 = &.{
    "Buffer.cpp",
    "Deprecations.cpp",
    "Drawable.cpp",
    "Font.cpp",
    "Graphics.cpp",
    "GraphicsReadback.cpp",
    "Mesh.cpp",
    "ParticleSystem.cpp",
    "Polyline.cpp",
    "Quad.cpp",
    "renderstate.cpp",
    "Shader.cpp",
    "ShaderStage.cpp",
    "SpriteBatch.cpp",
    "StreamBuffer.cpp",
    "TextBatch.cpp",
    "Texture.cpp",
    "vertex.cpp",
    "Video.cpp",
    "Volatile.cpp",
    "wrap_Buffer.cpp",
    "wrap_Font.cpp",
    "wrap_Graphics.cpp",
    "wrap_GraphicsReadback.cpp",
    "wrap_Mesh.cpp",
    "wrap_ParticleSystem.cpp",
    "wrap_Quad.cpp",
    "wrap_Shader.cpp",
    "wrap_SpriteBatch.cpp",
    "wrap_Texture.cpp",
    "wrap_TextBatch.cpp",
    "wrap_Video.cpp",
};

const graphics_opengl_srcs: []const []const u8 = &.{
    "opengl/Buffer.cpp",
    "opengl/FenceSync.cpp",
    "opengl/Graphics.cpp",
    "opengl/GraphicsReadback.cpp",
    "opengl/OpenGL.cpp",
    "opengl/Shader.cpp",
    "opengl/ShaderStage.cpp",
    "opengl/StreamBuffer.cpp",
    "opengl/Texture.cpp",
};

const graphics_vulkan_srcs: []const []const u8 = &.{
    "vulkan/Graphics.cpp",
    "vulkan/GraphicsReadback.cpp",
    "vulkan/Shader.cpp",
    "vulkan/ShaderStage.cpp",
    "vulkan/StreamBuffer.cpp",
    "vulkan/Buffer.cpp",
    "vulkan/Texture.cpp",
    "vulkan/Vulkan.cpp",
};

const image_common_srcs: []const []const u8 = &.{
    "CompressedImageData.cpp",
    "CompressedSlice.cpp",
    "FormatHandler.cpp",
    "Image.cpp",
    "ImageData.cpp",
    "ImageDataBase.cpp",
    "wrap_CompressedImageData.cpp",
    "wrap_Image.cpp",
    "wrap_ImageData.cpp",
};

const image_magpie_srcs: []const []const u8 = &.{
    "magpie/ASTCHandler.cpp",
    "magpie/ddsHandler.cpp",
    "magpie/EXRHandler.cpp",
    "magpie/KTXHandler.cpp",
    "magpie/PKMHandler.cpp",
    "magpie/PNGHandler.cpp",
    "magpie/PVRHandler.cpp",
    "magpie/STBHandler.cpp",
};

const joystick_common_srcs: []const []const u8 = &.{
    "Joystick.cpp",
    "wrap_Joystick.cpp",
    "wrap_JoystickModule.cpp",
};

const joystick_sdl_srcs: []const []const u8 = &.{
    "sdl/Joystick.cpp",
    "sdl/JoystickModule.cpp",
};

const keyboard_common_srcs: []const []const u8 = &.{
    "Keyboard.cpp",
    "wrap_Keyboard.cpp",
};

const keyboard_sdl_srcs: []const []const u8 = &.{
    "sdl/Keyboard.cpp",
};

const math_common_srcs: []const []const u8 = &.{
    "BezierCurve.cpp",
    "MathModule.cpp",
    "RandomGenerator.cpp",
    "Transform.cpp",
    "wrap_BezierCurve.cpp",
    "wrap_Math.cpp",
    "wrap_RandomGenerator.cpp",
    "wrap_Transform.cpp",
};

const mouse_common_srcs: []const []const u8 = &.{
    "Cursor.cpp",
    "wrap_Cursor.cpp",
    "wrap_Mouse.cpp",
};

const mouse_sdl_srcs: []const []const u8 = &.{
    "sdl/Cursor.cpp",
    "sdl/Mouse.cpp",
};

const physics_common_srcs: []const []const u8 = &.{
    "Body.cpp",
    "Joint.cpp",
    "Shape.cpp",
};

const physics_box2d_srcs: []const []const u8 = &.{
    "box2d/Body.cpp",
    "box2d/ChainShape.cpp",
    "box2d/CircleShape.cpp",
    "box2d/Contact.cpp",
    "box2d/DistanceJoint.cpp",
    "box2d/EdgeShape.cpp",
    "box2d/FrictionJoint.cpp",
    "box2d/GearJoint.cpp",
    "box2d/Joint.cpp",
    "box2d/MotorJoint.cpp",
    "box2d/MouseJoint.cpp",
    "box2d/Physics.cpp",
    "box2d/PolygonShape.cpp",
    "box2d/PrismaticJoint.cpp",
    "box2d/PulleyJoint.cpp",
    "box2d/RevoluteJoint.cpp",
    "box2d/RopeJoint.cpp",
    "box2d/Shape.cpp",
    "box2d/WeldJoint.cpp",
    "box2d/WheelJoint.cpp",
    "box2d/World.cpp",
    "box2d/wrap_Body.cpp",
    "box2d/wrap_ChainShape.cpp",
    "box2d/wrap_CircleShape.cpp",
    "box2d/wrap_Contact.cpp",
    "box2d/wrap_DistanceJoint.cpp",
    "box2d/wrap_EdgeShape.cpp",
    "box2d/wrap_FrictionJoint.cpp",
    "box2d/wrap_GearJoint.cpp",
    "box2d/wrap_Joint.cpp",
    "box2d/wrap_MotorJoint.cpp",
    "box2d/wrap_MouseJoint.cpp",
    "box2d/wrap_Physics.cpp",
    "box2d/wrap_PolygonShape.cpp",
    "box2d/wrap_PrismaticJoint.cpp",
    "box2d/wrap_PulleyJoint.cpp",
    "box2d/wrap_RevoluteJoint.cpp",
    "box2d/wrap_RopeJoint.cpp",
    "box2d/wrap_Shape.cpp",
    "box2d/wrap_WeldJoint.cpp",
    "box2d/wrap_WheelJoint.cpp",
    "box2d/wrap_World.cpp",
};

const sensor_common_srcs: []const []const u8 = &.{
    "Sensor.cpp",
    "wrap_Sensor.cpp",
};
const sensor_sdl_srcs: []const []const u8 = &.{
    "sdl/Sensor.cpp",
};

const sound_common_srcs: []const []const u8 = &.{
    "Decoder.cpp",
    "Sound.cpp",
    "SoundData.cpp",
    "wrap_Decoder.cpp",
    "wrap_Sound.cpp",
    "wrap_SoundData.cpp",
};
const sound_lullaby_srcs: []const []const u8 = &.{
    "lullaby/FLACDecoder.cpp",
    "lullaby/ModPlugDecoder.cpp",
    "lullaby/MP3Decoder.cpp",
    "lullaby/Sound.cpp",
    "lullaby/VorbisDecoder.cpp",
    "lullaby/WaveDecoder.cpp",
};

const system_common_srcs: []const []const u8 = &.{
    "System.cpp",
    "wrap_System.cpp",
};
const system_sdl_srcs: []const []const u8 = &.{
    "sdl/System.cpp",
};

const thread_common_srcs: []const []const u8 = &.{
    "Channel.cpp",
    "LuaThread.cpp",
    "ThreadModule.cpp",
    "threads.cpp",
    "wrap_Channel.cpp",
    "wrap_LuaThread.cpp",
    "wrap_ThreadModule.cpp",
};
const thread_sdl_srcs: []const []const u8 = &.{
    "sdl/Thread.cpp",
    "sdl/threads.cpp",
};

const timer_common_srcs: []const []const u8 = &.{
    "Timer.cpp",
    "wrap_Timer.cpp"
};

const touch_common_srcs: []const []const u8 = &.{
    "Touch.cpp",
    "wrap_Touch.cpp",
};
const touch_sdl_srcs: []const []const u8 = &.{
    "sdl/Touch.cpp",
};

const video_common_srcs: []const []const u8 = &.{
    "VideoStream.cpp",
    "wrap_Video.cpp",
    "wrap_VideoStream.cpp",
};
const video_theora_srcs: []const []const u8 = &.{
    "theora/Video.cpp",
    "theora/OggDemuxer.cpp",
    "theora/TheoraVideoStream.cpp",
};

const window_common_srcs: []const []const u8 = &.{
    "Window.cpp",
    "wrap_Window.cpp",
};
const window_sdl_srcs: []const []const u8 = &.{
    "sdl/Window.cpp",
};

const enet_srcs: []const []const u8 = &.{};
const luasocket_srcs: []const []const u8 = &.{};
const luahttps_srcs: []const []const u8 = &.{};
const spirv_cross_srcs: []const []const u8 = &.{};
