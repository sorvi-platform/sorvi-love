extern fn __PHYSFS_strdup([*:0]const u8) callconv(.c) [*:0]u8;

export fn __PHYSFS_platformInit() c_int {
    return 1;
}

export fn __PHYSFS_platformDeinit() void {}

export fn __PHYSFS_platformDetectAvailableCDs(_: *anyopaque, _: ?*anyopaque) void {}

export fn __PHYSFS_platformCalcBaseDir(_: [*:0]const u8) ?[*:0]u8 {
    return __PHYSFS_strdup("/core/");
}

export fn __PHYSFS_platformCalcPrefDir(_: [*:0]const u8, _: [*:0]const u8) ?[*:0]u8 {
    return __PHYSFS_strdup("/data/");
}
