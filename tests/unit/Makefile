# Tests for the driver's pure code, built in userspace under ASan and UBSan.
# No card or kernel headers needed.
#
#   make -C tests/unit check

SRC := ../../src
# GCC needs libasan and libubsan installed; clang's runtime comes with compiler-rt
CC ?= cc
SAN := -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
CFLAGS ?= -O1 -g
CFLAGS += -std=gnu11 $(SAN) -I$(SRC)
STRICT := -Wall -Wextra -Werror
LDFLAGS += $(SAN)

all: test_calc

test_calc: test_calc.c $(SRC)/hws_calc.h
	$(CC) $(CFLAGS) $(STRICT) -o $@ $< $(LDFLAGS)

check: test_calc
	./test_calc

clean:
	rm -f test_calc

.PHONY: all check clean
