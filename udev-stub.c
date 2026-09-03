/*
 * udev-stub.c — no-op libudev replacement, loaded via LD_PRELOAD.
 *
 * Vivado enumerates USB devices through libudev at startup. Under
 * Docker Desktop's Rosetta emulation this crashes with a glibc
 * allocator abort inside udev_enumerate_scan_devices()
 * (docker/for-mac#7320). There are no USB devices inside the
 * container anyway (no USB passthrough on macOS), so every udev
 * call can safely report "nothing found".
 *
 * Build: gcc -shared -fPIC -o libudev-stub.so udev-stub.c
 * Use:   LD_PRELOAD=/path/to/libudev-stub.so vivado
 */

#include <stddef.h>

/* Opaque handles: every constructor returns NULL, every iterator is empty. */

void *udev_new(void) { return NULL; }
void *udev_ref(void *u) { return u; }
void *udev_unref(void *u) { (void)u; return NULL; }

void *udev_enumerate_new(void *u) { (void)u; return NULL; }
void *udev_enumerate_ref(void *e) { return e; }
void *udev_enumerate_unref(void *e) { (void)e; return NULL; }
int udev_enumerate_add_match_subsystem(void *e, const char *s) { (void)e; (void)s; return 0; }
int udev_enumerate_add_match_sysattr(void *e, const char *a, const char *v) { (void)e; (void)a; (void)v; return 0; }
int udev_enumerate_add_match_property(void *e, const char *p, const char *v) { (void)e; (void)p; (void)v; return 0; }
int udev_enumerate_scan_devices(void *e) { (void)e; return 0; }
void *udev_enumerate_get_list_entry(void *e) { (void)e; return NULL; }

void *udev_list_entry_get_next(void *le) { (void)le; return NULL; }
const char *udev_list_entry_get_name(void *le) { (void)le; return NULL; }
const char *udev_list_entry_get_value(void *le) { (void)le; return NULL; }

void *udev_device_new_from_syspath(void *u, const char *p) { (void)u; (void)p; return NULL; }
void *udev_device_new_from_devnum(void *u, char t, unsigned long n) { (void)u; (void)t; (void)n; return NULL; }
void *udev_device_ref(void *d) { return d; }
void *udev_device_unref(void *d) { (void)d; return NULL; }
void *udev_device_get_parent(void *d) { (void)d; return NULL; }
void *udev_device_get_parent_with_subsystem_devtype(void *d, const char *s, const char *t) { (void)d; (void)s; (void)t; return NULL; }
const char *udev_device_get_devnode(void *d) { (void)d; return NULL; }
const char *udev_device_get_syspath(void *d) { (void)d; return NULL; }
const char *udev_device_get_sysname(void *d) { (void)d; return NULL; }
const char *udev_device_get_subsystem(void *d) { (void)d; return NULL; }
const char *udev_device_get_devtype(void *d) { (void)d; return NULL; }
const char *udev_device_get_sysattr_value(void *d, const char *a) { (void)d; (void)a; return NULL; }
const char *udev_device_get_property_value(void *d, const char *p) { (void)d; (void)p; return NULL; }
void *udev_device_get_properties_list_entry(void *d) { (void)d; return NULL; }

void *udev_enumerate_get_udev(void *e) { (void)e; return NULL; }
int udev_enumerate_add_match_sysname(void *e, const char *n) { (void)e; (void)n; return 0; }
int udev_enumerate_add_match_parent(void *e, void *p) { (void)e; (void)p; return 0; }
int udev_enumerate_add_match_tag(void *e, const char *t) { (void)e; (void)t; return 0; }
int udev_enumerate_add_match_is_initialized(void *e) { (void)e; return 0; }
int udev_enumerate_add_nomatch_subsystem(void *e, const char *s) { (void)e; (void)s; return 0; }
int udev_enumerate_add_nomatch_sysattr(void *e, const char *a, const char *v) { (void)e; (void)a; (void)v; return 0; }
int udev_enumerate_scan_subsystems(void *e) { (void)e; return 0; }
int udev_enumerate_add_syspath(void *e, const char *p) { (void)e; (void)p; return 0; }
void *udev_device_get_udev(void *d) { (void)d; return NULL; }
void *udev_device_new_from_subsystem_sysname(void *u, const char *s, const char *n) { (void)u; (void)s; (void)n; return NULL; }
void *udev_device_new_from_device_id(void *u, const char *id) { (void)u; (void)id; return NULL; }
void *udev_device_new_from_environment(void *u) { (void)u; return NULL; }
const char *udev_device_get_devpath(void *d) { (void)d; return NULL; }
const char *udev_device_get_driver(void *d) { (void)d; return NULL; }
const char *udev_device_get_action(void *d) { (void)d; return NULL; }
unsigned long udev_device_get_devnum(void *d) { (void)d; return 0; }
const char *udev_device_get_sysnum(void *d) { (void)d; return NULL; }
unsigned long long udev_device_get_seqnum(void *d) { (void)d; return 0; }
unsigned long long udev_device_get_usec_since_initialized(void *d) { (void)d; return 0; }
int udev_device_get_is_initialized(void *d) { (void)d; return 0; }
int udev_device_has_tag(void *d, const char *t) { (void)d; (void)t; return 0; }
void *udev_device_get_devlinks_list_entry(void *d) { (void)d; return NULL; }
void *udev_device_get_tags_list_entry(void *d) { (void)d; return NULL; }
void *udev_device_get_sysattr_list_entry(void *d) { (void)d; return NULL; }
int udev_device_set_sysattr_value(void *d, const char *a, const char *v) { (void)d; (void)a; (void)v; return -1; }
void *udev_list_entry_get_by_name(void *le, const char *n) { (void)le; (void)n; return NULL; }
int udev_util_encode_string(const char *s, char *dst, unsigned long len) { (void)s; if (dst && len) dst[0]=0; return 0; }

void *udev_monitor_new_from_netlink(void *u, const char *n) { (void)u; (void)n; return NULL; }
void *udev_monitor_ref(void *m) { return m; }
void *udev_monitor_unref(void *m) { (void)m; return NULL; }
int udev_monitor_filter_add_match_subsystem_devtype(void *m, const char *s, const char *t) { (void)m; (void)s; (void)t; return 0; }
int udev_monitor_enable_receiving(void *m) { (void)m; return -1; }
int udev_monitor_get_fd(void *m) { (void)m; return -1; }
void *udev_monitor_receive_device(void *m) { (void)m; return NULL; }
