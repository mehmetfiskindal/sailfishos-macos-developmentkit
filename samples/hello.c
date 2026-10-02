#include <stdio.h>
#include <gnu/libc-version.h>

int main(void) {
    printf("Hello Sailfish, C / glibc %s\n", gnu_get_libc_version());
    return 0;
}
