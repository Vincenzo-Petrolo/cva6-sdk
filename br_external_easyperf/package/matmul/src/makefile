CC      := gcc
CFLAGS  := -O3 -march=native -mtune=native -pipe -std=c11 -Wall -Wextra -fno-omit-frame-pointer
LDFLAGS := 

SRC := main.c

.PHONY: all clean
all: matmul64 matmul128 matmul256

matmul64: $(SRC)
	$(CC) $(CFLAGS) -DN=64  $(SRC) -o $@ $(LDFLAGS)

matmul128: $(SRC)
	$(CC) $(CFLAGS) -DN=128 $(SRC) -o $@ $(LDFLAGS)

matmul256: $(SRC)
	$(CC) $(CFLAGS) -DN=256 $(SRC) -o $@ $(LDFLAGS)

clean:
	$(RM) matmul64 matmul128 matmul256
