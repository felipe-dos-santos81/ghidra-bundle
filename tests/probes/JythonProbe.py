# Prints "JYTHON OK <version>" when Ghidra runs this script under Jython, and
# "JYTHON WRONG <platform>" under any other Python runtime.
# @category Bundle
# @runtime Jython
import sys

if sys.platform.startswith("java"):
    print("JYTHON OK " + sys.version.split()[0])
else:
    print("JYTHON WRONG " + sys.platform)
