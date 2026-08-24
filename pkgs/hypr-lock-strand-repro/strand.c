/* hypr-lock-strand-repro
 *
 * Detects a compositor that returns from ext_session_lock_v1.get_lock_surface
 * without creating an object for the client-allocated new_id. The client is
 * then holding a proxy the server does not know, and dies on its next request
 * to it: wl_display.error(0, "invalid object N"), which is fatal.
 *
 * Locks and unlocks the session BEFORE the request under test, so a kill
 * cannot leave the session locked. Never reads input, never authenticates.
 *
 * exit: 0 survived, 1 killed, 2 skipped (preconditions unmet), 3 error
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <wayland-client.h>

#include "ext-session-lock-v1-client-protocol.h"

#define EXIT_SURVIVED 0
#define EXIT_KILLED   1
#define EXIT_SKIPPED  2
#define EXIT_ERROR    3

static struct wl_compositor              *compositor;
static struct ext_session_lock_manager_v1 *lock_manager;
static struct wl_output                   *output;

/* Per-lock state, so one listener serves both lock objects. */
struct lock_state {
    bool locked;
    bool finished;
};

static void on_locked(void *data, struct ext_session_lock_v1 *lock) {
    (void)lock;
    ((struct lock_state *)data)->locked = true;
}

static void on_finished(void *data, struct ext_session_lock_v1 *lock) {
    (void)lock;
    ((struct lock_state *)data)->finished = true;
}

static const struct ext_session_lock_v1_listener lock_listener = {
    .locked   = on_locked,
    .finished = on_finished,
};

static uint32_t min_u32(uint32_t a, uint32_t b) {
    return a < b ? a : b;
}

static void reg_global(void *data, struct wl_registry *reg, uint32_t name,
                       const char *iface, uint32_t ver) {
    (void)data;
    if (strcmp(iface, wl_compositor_interface.name) == 0) {
        compositor = wl_registry_bind(reg, name, &wl_compositor_interface, min_u32(ver, 4));
    } else if (strcmp(iface, ext_session_lock_manager_v1_interface.name) == 0) {
        lock_manager = wl_registry_bind(reg, name, &ext_session_lock_manager_v1_interface, 1);
    } else if (strcmp(iface, wl_output_interface.name) == 0 && output == NULL) {
        output = wl_registry_bind(reg, name, &wl_output_interface, min_u32(ver, 3));
    }
}

static void reg_remove(void *data, struct wl_registry *reg, uint32_t name) {
    (void)data; (void)reg; (void)name;
}

static const struct wl_registry_listener reg_listener = {
    .global        = reg_global,
    .global_remove = reg_remove,
};

/* Round-trip; describe a protocol error if one killed us. 0 = keep going. */
static int settle(struct wl_display *dpy, const char *stage) {
    if (wl_display_roundtrip(dpy) >= 0)
        return 0;

    int err = wl_display_get_error(dpy);
    if (err != EPROTO) {
        printf("RESULT: ERROR\n");
        printf("  stage = %s\n", stage);
        printf("  errno = %d (%s)\n", err, strerror(err));
        return EXIT_ERROR;
    }

    const struct wl_interface *iface = NULL;
    uint32_t                   id    = 0;
    uint32_t                   code  = wl_display_get_protocol_error(dpy, &iface, &id);

    printf("RESULT: KILLED by protocol error\n");
    printf("  stage        = %s\n", stage);
    printf("  interface    = %s\n", iface && iface->name ? iface->name : "(unknown)");
    printf("  object id    = %u\n", id);
    printf("  error code   = %u", code);
    if (iface && iface->name && strcmp(iface->name, "wl_display") == 0 && code == 0)
        printf("   (wl_display.error.invalid_object)");
    printf("\n");
    printf("\n");
    printf("  libwayland logged the compositor's message to stderr above; it\n");
    printf("  names the stranded id, e.g. \"invalid object 550\".\n");
    return EXIT_KILLED;
}

static void usage(const char *argv0) {
    printf("usage: %s [--help]\n", argv0);
    printf("\n");
    printf("Checks whether this Wayland compositor strands a client-allocated\n");
    printf("object id when ext_session_lock_v1.get_lock_surface cannot be\n");
    printf("honoured.\n");
    printf("\n");
    printf("Requires a compositor that denies a second concurrent session lock,\n");
    printf("which is the default. On Hyprland that means\n");
    printf("  misc:allow_session_lock_restore = false\n");
    printf("With it enabled the second lock is neither granted nor denied and\n");
    printf("this check cannot run; it reports SKIPPED rather than guessing.\n");
    printf("\n");
    printf("The session is locked and unlocked again before the request under\n");
    printf("test is sent. Exit: 0 survived, 1 killed, 2 skipped, 3 error.\n");
}

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return EXIT_SURVIVED;
        }
        fprintf(stderr, "unknown argument: %s\n", argv[i]);
        usage(argv[0]);
        return EXIT_ERROR;
    }

    struct wl_display *dpy = wl_display_connect(NULL);
    if (!dpy) {
        printf("RESULT: ERROR\n");
        printf("  cannot connect to a Wayland display (is WAYLAND_DISPLAY set?)\n");
        return EXIT_ERROR;
    }

    struct wl_registry *reg = wl_display_get_registry(dpy);
    wl_registry_add_listener(reg, &reg_listener, NULL);
    if (wl_display_roundtrip(dpy) < 0) {
        printf("RESULT: ERROR\n  registry round-trip failed\n");
        return EXIT_ERROR;
    }

    if (!compositor || !output) {
        printf("RESULT: ERROR\n  compositor did not advertise wl_compositor and wl_output\n");
        return EXIT_ERROR;
    }
    if (!lock_manager) {
        printf("RESULT: SKIPPED\n");
        printf("  this compositor does not implement ext-session-lock-v1\n");
        return EXIT_SKIPPED;
    }

    /* 1. Take the lock. The compositor grants this one. */
    struct lock_state st1 = {0};
    struct ext_session_lock_v1 *lock1 = ext_session_lock_manager_v1_lock(lock_manager);
    ext_session_lock_v1_add_listener(lock1, &lock_listener, &st1);
    int rc = settle(dpy, "first lock");
    if (rc)
        return rc;

    if (!st1.locked) {
        printf("RESULT: SKIPPED\n");
        printf("  the compositor did not grant the first lock%s\n",
               st1.finished ? " (it sent finished)" : "");
        printf("  something else may already hold a session lock\n");
        return EXIT_SKIPPED;
    }

    /* 2. Ask again. A conforming compositor denies it and sends finished
     *    immediately; Hyprland marks that lock m_inert. */
    struct lock_state st2 = {0};
    struct ext_session_lock_v1 *lock2 = ext_session_lock_manager_v1_lock(lock_manager);
    ext_session_lock_v1_add_listener(lock2, &lock_listener, &st2);
    rc = settle(dpy, "second lock");
    if (rc)
        return rc;

    if (!st2.finished) {
        /* Put the screen back before bailing out. */
        ext_session_lock_v1_unlock_and_destroy(lock1);
        wl_display_roundtrip(dpy);
        printf("RESULT: SKIPPED\n");
        printf("  the second lock was neither denied nor granted, so the code\n");
        printf("  path under test was never entered.\n");
        printf("  on Hyprland: set misc:allow_session_lock_restore = false\n");
        return EXIT_SKIPPED;
    }

    /* 3. Lock surface on the DENIED lock. The id is spent here; a compositor
     *    that returns without constructing has now silently desynced. */
    struct wl_surface *surface = wl_compositor_create_surface(compositor);
    struct ext_session_lock_surface_v1 *ls =
        ext_session_lock_v1_get_lock_surface(lock2, surface, output);
    uint32_t ls_id = wl_proxy_get_id((struct wl_proxy *)ls);
    printf("allocated ext_session_lock_surface_v1 id %u on the denied lock\n", ls_id);

    /* 4. Restore the screen before the request under test. */
    ext_session_lock_v1_unlock_and_destroy(lock1);
    rc = settle(dpy, "unlocking");
    if (rc)
        return rc;

    /* 5. Legal: destroy is only an error if `locked` was sent, and it was not.
     *    Objects created through the lock "remain valid" after it. */
    ext_session_lock_v1_destroy(lock2);
    rc = settle(dpy, "destroying the denied lock");
    if (rc)
        return rc;

    /* 6. Touch the possibly-stranded id. This is the whole test. */
    printf("destroying id %u ...\n", ls_id);
    fflush(stdout);
    ext_session_lock_surface_v1_destroy(ls);

    rc = settle(dpy, "destroying the lock surface");
    if (rc)
        return rc;

    printf("RESULT: SURVIVED\n");
    printf("  the compositor created an object for id %u, so destroying it was\n", ls_id);
    printf("  harmless. This compositor is not affected.\n");

    wl_surface_destroy(surface);
    wl_display_disconnect(dpy);
    return EXIT_SURVIVED;
}
