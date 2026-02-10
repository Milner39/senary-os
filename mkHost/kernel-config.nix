# baseline kernel config (structured)
{
  # turning this off may hide other options, so it's most useful to force it on
  EXPERT = "y";

  # sixos needs kexec() to work
  KEXEC = "y";
}
