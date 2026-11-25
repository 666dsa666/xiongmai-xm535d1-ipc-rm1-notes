/*
 * block80.so - LD_PRELOAD shim for Xiongmai V5.07 Sofia (XM535D1).
 *
 * Purpose: make Sofia's HTTP/web server unable to bind TCP port 80, without
 * touching the RTSP (554), ONVIF (8899) or DVRIP (34567) listeners and
 * without patching the vendor binary.
 *
 * Design constraints:
 *  - target is uClibc-1.0.26 ld.so + libc.so.0 on ARM EABI (soft-float).
 *  - fully freestanding: no libc, libgcc or unwind dependencies.  The real
 *    bind(2) is issued with an inline "svc 0" so this object never needs a
 *    libc symbol; only a *weak* __errno_location is referenced (resolved by
 *    the already-loaded libc when available).
 *  - built with --hash-style=sysv because uClibc's ld.so predates GNU hash.
 *
 * Behaviour:
 *  - bind(AF_INET, port 80) -> -1 / errno EACCES (default: BLOCK).
 *    Optional BLOCK80_REDIRECT_PORT env var makes it bind that port instead
 *    (used only if the caller proves to treat a hard failure as fatal).
 *  - every other bind is passed through to the kernel unchanged.
 *
 * A constructor writes a one-line marker to /var/block80.log so a QEMU boot
 * proves the object was really preloaded (the vendor redirects Sofia's stdout
 * to /var/sofia.log; a failed LD_PRELOAD would also be visible there).
 */

typedef int s32;
typedef unsigned int u32;

#define AF_INET 2

/* ARM EABI direct syscall numbers (asm/unistd.h, arch/arm) */
#define __NR_write 4
#define __NR_open  5
#define __NR_close 6
#define __NR_bind  282

#define O_WRONLY 1
#define O_CREAT  0100
#define O_APPEND 02000
#define O_TRUNC  01000

extern int *__errno_location(void) __attribute__((weak));

static inline s32 syscall3(s32 nr, s32 a, s32 b, s32 c)
{
    register s32 r0 __asm__("r0") = a;
    register s32 r1 __asm__("r1") = b;
    register s32 r2 __asm__("r2") = c;
    register s32 r7 __asm__("r7") = nr;
    __asm__ volatile("svc 0"
                     : "+r"(r0)
                     : "r"(r1), "r"(r2), "r"(r7)
                     : "memory");
    return r0;
}

static inline s32 sys_bind(int fd, const void *addr, u32 len)
{
    register s32 r0 __asm__("r0") = fd;
    register const void *r1 __asm__("r1") = addr;
    register u32 r2 __asm__("r2") = len;
    register s32 r7 __asm__("r7") = __NR_bind;
    __asm__ volatile("svc 0"
                     : "+r"(r0)
                     : "r"(r1), "r"(r2), "r"(r7)
                     : "memory");
    return r0;
}

static void set_errno(int e)
{
    int *(*fn)(void) = __errno_location;
    if (fn) {
        int *p = fn();
        if (p)
            *p = e;
    }
}

static u32 slen(const char *s)
{
    u32 n = 0;
    while (s[n])
        n++;
    return n;
}

/* best-effort append of one line to /var/block80.log (fails silently) */
static void note(const char *msg)
{
    s32 fd = syscall3(__NR_open, (s32)"/var/block80.log",
                      O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0)
        return;
    syscall3(__NR_write, fd, (s32)msg, (s32)slen(msg));
    syscall3(__NR_close, fd, 0, 0);
}

/* tiny decimal formatter for the port value */
static char *fmt_port(char *end, unsigned v)
{
    char tmp[8];
    int i = 0;
    *--end = '\n';
    if (!v)
        *--end = '0';
    while (v) {
        tmp[i++] = '0' + (v % 10);
        v /= 10;
    }
    while (i)
        *--end = tmp[--i];
    return end;
}

/* optional redirect target, parsed from BLOCK80_REDIRECT_PORT (decimal),
 * read through libc's getenv (weak, so never a hard dependency) */
extern char *getenv(const char *name) __attribute__((weak));

static unsigned redirect_port(void)
{
    char *(*g)(const char *) = getenv;
    if (!g)
        return 0;
    const char *s = g("BLOCK80_REDIRECT_PORT");
    if (!s)
        return 0;
    unsigned v = 0;
    while (*s >= '0' && *s <= '9') {
        v = v * 10 + (unsigned)(*s - '0');
        if (v > 65535)
            return 0;
        s++;
    }
    return v;
}

__attribute__((visibility("default")))
int bind(int fd, const void *addr, u32 len)
{
    if (addr && len >= 8) {
        const unsigned char *b = (const unsigned char *)addr;
        unsigned family = (unsigned)b[0] | ((unsigned)b[1] << 8);
        unsigned port = ((unsigned)b[2] << 8) | (unsigned)b[3];
        if (family == AF_INET && port == 80) {
            unsigned rp = redirect_port();
            if (rp) {
                /* redirect: rewrite sin_port in a local copy, keep it alive
                 * on the stack for the duration of the syscall */
                unsigned char sa[16];
                u32 i;
                for (i = 0; i < sizeof(sa); i++)
                    sa[i] = (i < len) ? b[i] : 0;
                sa[2] = (unsigned char)(rp >> 8);
                sa[3] = (unsigned char)(rp & 0xff);
                s32 r = sys_bind(fd, sa, len < 16 ? len : 16);
                if (r < 0) {
                    set_errno(-r);
                    return -1;
                }
                note("lib block80: bind port 80 REDIRECTED to high port\n");
                return r;
            }
            set_errno(13 /* EACCES */);
            {
                char buf[48] = "lib block80: bind port 80 BLOCKED (EACCES)";
                u32 n = slen(buf);
                buf[n++] = '\n';
                buf[n] = 0;
                note(buf);
            }
            return -1;
        }
    }
    {
        s32 r = sys_bind(fd, addr, len);
        if (r < 0) {
            set_errno(-r);
            return -1;
        }
        return r;
    }
}

static void block80_init(void)
{
    note("lib block80: preload active (bind port 80 blocked)\n");
}

__attribute__((section(".init_array"), used))
static void (*block80_init_ptr)(void) = block80_init;
