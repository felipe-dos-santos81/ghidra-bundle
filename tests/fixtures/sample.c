/* Core-decompiler fixture for `make test` (see tests/expect/sample.txt).
 * Compiled with: clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c */
int counter;

__attribute__((noinline)) int helper(int x) { return x * 3 + 7; }

int compute(int a) {
  counter++;
  return helper(a) ^ 0x1234abcd;
}
