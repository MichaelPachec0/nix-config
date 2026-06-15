{
  ...
}: {
  config = {
    accounts.email = {
      acounts = {
        "codewars" = {address = "codewars@michaelpacheco.org";};
        "mp" = {
          address = "mp@michaelpacheco.org";
          gpg = {
            encryptedByDefault = true;
            signByDefault = true;
            key = "0x781146B0B5F95F64";
          };
        };
        "gpg" = {
          address = "gpg@michaelpacheco.org";
          gpg = {
            encryptedByDefault = true;
            signByDefault = true;
            key = "0x781146B0B5F95F64";
          };
        };
        "git" = {
          address = "git@michaelpacheco.org";
          gpg = {
            encryptedByDefault = true;
            signByDefault = true;
            key = "0x781146B0B5F95F64";
          };
        };
      };
    };
  };
}
