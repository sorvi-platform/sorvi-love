#ifndef _INCL_PHYSFS_PLATFORMS
#define _INCL_PHYSFS_PLATFORMS

#ifndef __PHYSICSFS_INTERNAL__
#  error Do not include this header from your applications.
#endif

#define PHYSFS_PLATFORM_SORVI 1
#define PHYSFS_PLATFORM_POSIX 1
#define PHYSFS_NO_CDROM_SUPPORT 1

#define PHYSFS_SUPPORTS_DEFAULT 0
#define PHYSFS_SUPPORTS_ZIP 1

#endif
