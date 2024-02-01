{
  pkgs,
  pinentryFlavor,
}: ''
  enable-ssh-support
  ttyname $GPG_TTY
  default-cache-ttl 60
  max-cache-ttl 120
  pinentry-program ${pkgs.pinentry.${pinentryFlavor}}/bin/pinentry
''
# https://github.com/drduh/config/blob/master/gpg-agent.conf
# https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html
# testing out shared-access, so that gpg and opensc work
# TODO: need to override this with a shared-access
