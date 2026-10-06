
uint compute(undefined4 param_1)

{
  uint uVar1;

  counter = counter + 1;
  uVar1 = helper(param_1);
  return uVar1 ^ 0x1234abcd;
}

