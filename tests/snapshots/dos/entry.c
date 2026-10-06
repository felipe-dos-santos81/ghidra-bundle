

void entry(void)

{
  DAT_1002_000e = 8;
  s_TESTDATA_1002_0000._0_2_ = FUN_1000_0010();
  swi(0x21);
  DosTerminateErrorCode(0);
}

