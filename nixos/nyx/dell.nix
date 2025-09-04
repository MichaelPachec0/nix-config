{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # dell-command-configure
  ];
}
