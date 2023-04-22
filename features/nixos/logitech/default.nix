# TODO: convert this to a proper module. Add a config setting, ..ect.
{ config, lib, pkgs, ... }:
let
  configText = ''
        // Logiops (Linux driver) configuration for Logitech MX Master 3.
    // Includes gestures, smartshift, DPI.
    // Tested on logid v0.2.3 - GNOME 3.38.4 on Zorin OS 16 Pro
    // What's working:
    //   1. Window snapping using Gesture button (Thumb)
    //   2. Forward Back Buttons
    //   3. Top button (Ratchet-Free wheel)
    // What's not working:
    //   1. Thumb scroll (H-scroll)
    //   2. Scroll button

    // File location: /etc/logid.cfg

    devices: ({
      name: "Wireless Mouse MX Master 3";

      smartshift: {
        on: true;
        threshold: 25;
      };
      thumbwheel: {
        divert: false;
        invert: false;
      };
      hiresscroll: {
        hires: true;
        invert: false;
        target: false;
      };

      dpi: 1500; // max=4000

      buttons: (
        // Forward button
        {
          cid: 0x56;
          action = {
            type: "Gestures";
            gestures: (
              {
                direction: "None";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_FORWARD" ];
                }
              },

              {
                direction: "Up";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_PLAYPAUSE" ];
                }
              },

              {
                direction: "Down";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_LEFTMETA" ];
                }
              },

              {
                direction: "Right";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_NEXTSONG" ];
                }
              },

              {
                direction: "Left";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_PREVIOUSSONG" ];
                }
              }
            );
          };
        },

        // Back button
        {
          cid: 0x53;
          action = {
            type: "Gestures";
            gestures: (
              {
                direction: "None";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_BACK" ];
                }
              }
            );
          };
        },

        // Gesture button (hold and move)
        {
          cid: 0xc3;
          action = {
            type: "Gestures";
            gestures: (
              {
                direction: "None";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_LEFTMETA" ]; // open activities overview
                }
              },

              {
                direction: "Right";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_LEFTMETA", "KEY_RIGHT" ]; // snap window to right
                }
              },

              {
                direction: "Left";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_LEFTMETA", "KEY_LEFT" ];
                }
    		  },

    		  {
                direction: "Up";
                mode: "onRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_LEFTMETA", "KEY_UP" ]; // maximize window
                }
    		  },
    		  
    		  {
                direction: "Down";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_LEFTMETA", "KEY_DOWN" ]; // minimize window
                }
              }
            );
          };
        },
    	
        // Top button
        {
          cid: 0xc4;
          action = {
            type: "Gestures";
            gestures: (
              {
                direction: "None";
                mode: "OnRelease";
                action = {
                  //type: "ToggleSmartShift";
                  type: "Keypress";
                  keys: ["KEY_LEFTCTRL", "KEY_UP"]; //fancy change window (alternative in kwin shorctuts
                }
              },

              {
                direction: "Up";
                mode: "OnRelease";
                action = {
                  type: "ChangeDPI";
                  inc: 1000,
                }
              },

              {
                direction: "Down";
                mode: "OnRelease";
                action = {
                  type: "ChangeDPI";
                  inc: -1000,
                }
              },
              {
                direction: "Left";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_LEFTMETA" , "KEY_COMMA" ];
                }
               },
              {
                direction: "Right";
                mode: "OnRelease";
                action = {
                  type: "Keypress";
                  keys: [ "KEY_LEFTMETA",  "KEY_DOT" ];
                }
              }
            );
          };
        },
        {
          // ScrollWheel Button
          cid: 0x52;
          action = {
            type: "Gestures";
            gestures: (
              {
                direction: "None";
                mode: "OnRelease";
                action = {
                  type: "ToggleSmartShift";
                }
              }
            );
          };
        }
      );
    });
  '';
  configFile = pkgs.writeText "logid.cfg" configText;
in {
  options = {
    services = {
      logid = { enable = lib.mkEnableOption "adds logid to the environment."; };
    };
  };
  config = let logid = config.services.logid.enable;
  in lib.mkIf logid {
    environment.systemPackages = with pkgs; [ logiops ];
    hardware.logitech.wireless = {
      enable = true;
      enableGraphical = true;
    };
    systemd.packages = [ pkgs.logiops ];
    environment.etc."logid.cfg".source = "${configFile}";
  };
}
