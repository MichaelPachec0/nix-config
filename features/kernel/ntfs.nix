self: super: {
  linuxZenWMuQSS = super.pkgs.linuxPackagesFor (super.pkgs.linux_zen.override {
    structuredExtraConfig = with super.lib.kernel; { SCHED_MUQSS = yes; };
    ignoreConfigErrors = true;
  });
}
