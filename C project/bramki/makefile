CFLAGS = -Wall -Wextra -Wno-implicit-fallthrough -std=gnu17 -fPIC -O2
LDFLAGS = -shared -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=reallocarray -Wl,--wrap=free -Wl,--wrap=strdup -Wl,--wrap=strndup

.PHONY: all clean

libnand.so: nand.o memory_tests.o
	@echo "linkowanie do libnand.c"
	gcc $(LDFLAGS) nand.o memory_tests.o -o libnand.so

nand.o: nand.c nand.h
	@echo "kompilacja nand.c"
	gcc $(CFLAGS) -c nand.c

memory_tests.o: memory_tests.c memory_tests.h
	@echo "kompilacja memory_tests.c"
	gcc $(CFLAGS) -c memory_tests.c

nand_example.o:
	gcc $(CFLAGS) -c nand_example.c

clean:
	@echo "usuwanie plikow utworzonych przez make"
	rm libnand.so nand.o memory_tests.o