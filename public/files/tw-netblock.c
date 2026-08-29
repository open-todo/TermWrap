// ============================================================================
//  tw-netblock — LD_PRELOAD network kill-switch for termwrap sandboxes
//
//  Intercepts libc socket()/getaddrinfo()/connect(). When the env var
//  TW_NETBLOCK=1 the sandbox fails CLOSED for AF_INET / AF_INET6 /
//  AF_NETLINK+AF_PACKET traffic with EACCES, so dynamically-linked agents
//  (python, node, ruby, curl, wget, git …) simply cannot open sockets.
//
//  Build:  cc -O2 -shared -fPIC tw-netblock.c -o netblock.so
//
//  Scope note: raw-syscall binaries (static, most Go) bypass LD_PRELOAD —
//  this is a safety rail for AI agents, not a kernel netns. See tw --caveats.
//
//  COPYRIGHT OPENTODO© — released under the MIT license.
// ============================================================================
#define _GNU_SOURCE
#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <dlfcn.h>

static int enabled(void) {
  const char *v = getenv("TW_NETBLOCK");
  return v && v[0] == '1';
}
static int loud(void) {
  return getenv("TW_NETBLOCK_LOG") != NULL;
}
static void note(const char *op, int domain) {
  if (loud())
    fprintf(stderr, "[tw-net] blocked %s(domain=%d) — sandbox is offline by policy\n",
            op, domain);
}
static int deny_domain(int d) {
  return d == AF_INET || d == AF_INET6 || d == AF_PACKET || d == AF_NETLINK;
}

typedef int (*socket_fn)(int, int, int);
typedef int (*connect_fn)(int, const struct sockaddr *, socklen_t);
typedef int (*ga_fn)(const char *, const char *, const struct addrinfo *,
                     struct addrinfo **);

int socket(int domain, int type, int protocol) {
  if (enabled() && deny_domain(domain)) {
    note("socket", domain);
    errno = EACCES;
    return -1;
  }
  static socket_fn real = NULL;
  if (!real) real = (socket_fn)dlsym(RTLD_NEXT, "socket");
  return real(domain, type, protocol);
}

// second line of defense for resolvers that grabbed a socket elsewhere
int connect(int fd, const struct sockaddr *addr, socklen_t len) {
  if (enabled() && addr &&
      (addr->sa_family == AF_INET || addr->sa_family == AF_INET6)) {
    note("connect", addr->sa_family);
    errno = EACCES;
    return -1;
  }
  static connect_fn real = NULL;
  if (!real) real = (connect_fn)dlsym(RTLD_NEXT, "connect");
  return real(fd, addr, len);
}

// fast, quiet failure for DNS so agents do not stall on timeouts
int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res) {
  if (enabled() && (!hints || hints->ai_family != AF_UNIX)) {
    if (loud())
      fprintf(stderr, "[tw-net] blocked getaddrinfo(\"%s\")\n",
              node ? node : "(null)");
    return EAI_NONAME;
  }
  static ga_fn real = NULL;
  if (!real) real = (ga_fn)dlsym(RTLD_NEXT, "getaddrinfo");
  return real(node, service, hints, res);
}
