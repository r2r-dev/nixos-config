# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
let
  wrapSystemdScript = (
    program: ''
      source ${config.system.build.setEnvironment}
      exec ${program}
    ''
  );
in rec {
  imports =
    [ # Include the results of the hardware scan.
      <nixos-hardware/lenovo/thinkpad/x260>
      "${builtins.fetchTarball https://github.com/rycee/home-manager/archive/master.tar.gz}/nixos"
      ./hardware-configuration.nix
    ];

  system.stateVersion = "18.09"; # Did you read the comment?
  home-manager.users.qwerty = {
    home.file = {
      # spacemacs
      ".emacs.d" = {
        source = fetchTarball https://github.com/syl20bnr/spacemacs/archive/master.tar.gz;
        recursive = true;
      };
      ".spacemacs".source = ./dotfiles/spacemacs;
      ".local/share/applications/org-protocol.desktop".source = ./dotfiles/org-protocol.desktop;
    };
  };

  # Only keep the last 500MiB of systemd journal.
  services.journald.extraConfig = "SystemMaxUse=500M";

  # Collect nix store garbage and optimise daily.
  nix.gc.automatic = true;
  nix.optimise.automatic = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.kernelModules = [ "vfat" "nls_cp437" "nls_iso8859-1" "usbhid" "kvm-intel" ];
  boot.initrd.luks.cryptoModules = [ "aes" "xts" "sha512" ];
  boot.initrd.luks.yubikeySupport = true;
  boot.initrd.luks.devices = [ {
    name = "luksroot";
    device = "/dev/disk/by-partlabel/cryptroot";
    preLVM = true;
    yubikey = {
      storage = {
        device = "/dev/disk/by-partlabel/efiboot";
      };
    };
  } ];

  swapDevices = [ { device = "/dev/partitions/swap"; } ];
  fileSystems."/" = {
    label = "root";
    device = "/dev/partitions/fsroot";
    fsType = "btrfs";
    options = [ "subvol=root" ];
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/efiboot";
    fsType = "vfat";
  };
  fileSystems."/home" = {
    label = "home";
    device = "/dev/partitions/fsroot";
    fsType = "btrfs";
    options = [ "subvol=home" ];
  };

  # Select internationalisation properties.
  i18n = {
    consoleFont = "Lat2-Terminus34";
    consoleKeyMap = "pl";
    defaultLocale = "en_US.UTF-8";
  };

  # Set your time zone.
  time.timeZone = "Europe/Warsaw";

  # Enable sound + pulseaudio
  sound.enable = true;
  hardware.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
  };

  # Enable bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  networking.hostName = "qwerty"; # Define your hostname.
#  networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.firewall = {
    # Ping is enabled
    allowPing = true;
    trustedInterfaces = [ "lo" ];
    # Ports for syncthing
    allowedTCPPorts = [ 22000 8080 8443 ];
    allowedUDPPorts = [ 21027 3478 ];
  };

 services.syncthing = {
    enable = true;
    user = "qwerty";
    dataDir = "/home/qwerty/.syncthing";
    openDefaultPorts = true;
};
  services.openssh = {
    enable = true;

    # Only pubkey auth - disable
    passwordAuthentication = true; # for now ...
    # challengeResponseAuthentication = false;
  };

  users.users.qwerty = {
    uid = 1000;
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "tty" "plugdev" "networkmanager" "docker" ];
  };
  users.extraGroups.plugdev = { };
  nixpkgs = {
     config.allowUnfree = true;
     config.packageOverrides = super: let self = super.pkgs; in {
       st = pkgs.callPackage ./ext-pkgs/st {
         conf = builtins.readFile ./ext-pkgs/st/st-config.h;
         patches =
           [
       ./ext-pkgs/st/st-vertcenter-20180320-6ac8c8a.diff
       ./ext-pkgs/st/st-alpha.diff
       ./ext-pkgs/st/st-xresources.diff ];
       };
       cmus = pkgs.callPackage ./ext-pkgs/cmus {};
       emacs = super.emacsWithPackages (ep: with ep; [
format-all
ace-link
ace-window
adaptive-wrap
aggressive-indent
company
company-quickhelp
flycheck
company-nixos-options
helm-nixos-options
nix-mode
nixos-options
nix-sandbox
ranger
alert
pdf-tools
frames-only-mode
anzu
#archives
async
auto-compile
auto-highlight-symbol
avy
bind-key
bind-map
clean-aindent-mode
cmm-mode
column-enforce-mode
company
company-ghc
company-ghci
dash
define-word
diminish
dumb-jump
elisp-slime-nav
epl
eval-sexp-fu
evil
evil-anzu
evil-args
evil-ediff
evil-escape
evil-exchange
evil-iedit-state
evil-indent-plus
evil-lisp-state
evil-matchit
evil-mc
evil-nerd-commenter
evil-numbers
evil-search-highlight-persist
evil-surround
evil-tutor
#evil-unimpaired
evil-visual-mark-mode
evil-visualstar
exec-path-from-shell
expand-region
eyebrowse
f
fancy-battery
fill-column-indicator
flx
flx-ido
flycheck
ghc
gntp
#gnupg
gnuplot
golden-ratio
google-translate
goto-chg
haskell-mode
haskell-snippets
helm
helm-ag
helm-core
helm-descbinds
helm-flx
helm-hoogle
helm-make
helm-mode-manager
helm-projectile
helm-swoop
helm-themes
highlight
highlight-indentation
highlight-numbers
highlight-parentheses
hindent
hlint-refactor
hl-todo
htmlize
hungry-delete
hydra
iedit
indent-guide
intero
link-hint
linum-relative
log4e
lorem-ipsum
macrostep
move-text
neotree
open-junk-file
org-bullets
org-category-capture
org-download
org-mime
org-plus-contrib
org-pomodoro
org-present
org-projectile
org-ref
ox-reveal
auctex
interleave
nyan-mode
treemacs
treemacs-evil
magit
markdown-mode
helm-bibtex
biblio
biblio-core
packed
paradox
parent-mode
pcre2el
persp-mode
pkg-info
popup
popwin
powerline
projectile
rainbow-delimiters
request
restart-emacs
s
smartparens
spaceline
spinner
toc-org
undo-tree
use-package
uuidgen
vi-tilde-fringe
volatile-highlights
which-key
winum
ws-butler
yasnippet
ace-jump-helm-line
adaptive-wrap
spinner
undo-tree
]);

    };
  };
  programs.java.enable = true;

  environment.systemPackages = with pkgs;
  [
    desktop-file-utils
    openvpn
    screen
    minicom
    xdotool
    keynav
    arandr
    appimage-run
    tcpdump
    wireshark
    python36
    autorandr
    easyrsa
    i3lock-fancy
    libreoffice
    jq
    slock
    wget
    tmux
    syncthing
    wmctrl
    cmus
    git
    nmap
    file
    fortune
    figlet
    aspell
    aspellDicts.en
    haskellPackages.brittany
    haskellPackages.pandoc
    htop
    zotero
    man-pages
    playerctl
    gtypist
    spotify
    keepassxc
    unzip
    stow
    lxqt.lxqt-openssh-askpass
    texlive.combined.scheme-full
    rtv
    emacs
    firefox
    feh
    qutebrowser
    mpv
    python36Packages.mps-youtube
    haskellPackages.xmobar
    udiskie
    udisks2
    unclutter
    xclip
    zathura
    compton
    neofetch
    easytag
    ranger
    rofi
    inkscape
    scrot
    gimp
    papirus-icon-theme
    lightdm-mini-greeter
    xorg.xmodmap
    yubioath-desktop
    pavucontrol
    gptfdisk
    yubikey-personalization
    transmission
    p7zip
    xorg.xbacklight
    gnupg
    ntfs3g
    python36Packages.binwalk-full
    xmind
    calibre
    gnome3.simple-scan
    vagrant
    packer
    mitmproxy
  ];

  # for smartcards
  services.pcscd.enable = true;

  # for ios tethering
  services.usbmuxd.enable = true;

  services.udev.packages = with pkgs; [
    yubikey-personalization
  ];
  services.emacs = {
    enable = true;
    defaultEditor = true;
  };

  virtualisation.virtualbox.host = {
    enable = true;
    enableExtensionPack = true;
  };

  virtualisation.docker.enable = true;
  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.desktopManager = {
    xterm.enable = false;
  };
  services.xserver.dpi = 110;
  services.xserver.autorun = true;
  services.xserver.layout = "pl";

  # scanning
  hardware.sane.enable = true;
  hardware.sane.extraBackends = [ pkgs.hplipWithPlugin ];

  services.printing = {
    enable = true;
    drivers = [ pkgs.hplip ];
  };

  # Enable xmonad and include extra packages
  services.xserver.windowManager.default = "xmonad";
  services.xserver.windowManager.xmonad = {
    enable = true;
    enableContribAndExtras = true;
    extraPackages = haskellPackages: [
      haskellPackages.xmonad-contrib
      haskellPackages.xmonad-extras
      haskellPackages.xmonad
    ];
  };

  # Use lightdm
  services.xserver.displayManager = {
    lightdm = {
      enable = true;
      greeters.mini.enable = true;
      greeters.mini.user = "qwerty";
      greeters.mini.extraConfig = ''
[greeter]
# Whether to show the password input's label.
show-password-label = false
# Show a blinking cursor in the password input.
show-input-cursor = true

[greeter-hotkeys]
# The modifier key used to trigger hotkeys. Possible values are:
# "alt", "control" or "meta"
# meta is also known as the "Windows"/"Super" key
mod-key = meta
# Power management shortcuts (single-key, case-sensitive)
shutdown-key = s
restart-key = r
hibernate-key = h
suspend-key = u


[greeter-theme]
# A color from X11's `rgb.txt` file, a quoted hex string(`"#rrggbb"`) or a
# RGB color(`rgb(r,g,b)`) are all acceptable formats.

# The font to use for all text
font = "Sans"
# The font size to use for all text
font-size = 1em
# The default text color
text-color = "#080800"
# The color of the error text
error-color = "#F8F8F0"
# An absolute path to an optional background image.
# The image will be displayed centered & unscaled.
background-image = ""
# The screen's background color.
background-color = "#1B1D1E"
# The password window's background color
window-color = "#282A36"
# The color of the password window's border
border-color = "#CAA9FA"
# The width of the password window's border.
# A trailing `px` is required.
border-width = 2px
# The pixels of empty space around the password input.
# Do not include a trailing `px`.
layout-space = 15
# The color of the text in the password input.
password-color = "#BFBFBF"
# The background color of the password input.
password-background-color = "#282A36"
'';
    };
  };

  services.redshift = {
    enable = false; 
    latitude = "40.7128";
    longitude = "-74.0060";
    temperature = {
      day = 6500;
      night = 3000;
    };
  };

  fonts = {
    enableFontDir = true;
    fonts = with pkgs; [
      font-awesome-ttf
      terminus_font
      inconsolata
      #nerdfonts # find actual pkgs you use fonts from ...
      opensans-ttf
      siji
    ];
  };
  programs.light.enable = true;
  services.udisks2.enable  = true;
  systemd.user.services = {
    udiskie = {
      description = "Mounts disks in userspace with udisks";
      serviceConfig = {
        Type    = "simple";
        Restart = "always";
      };
      script = wrapSystemdScript ''
        ${pkgs.udiskie}/bin/udiskie \
          -2                        \
          --smart-tray              \
          --automount               \
          --no-config               \
          --no-password-cache       \
          --no-notify               \
          --password-prompt ${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass
      '';
      wantedBy = [ "default.target" ];
    };
  };

  networking.networkmanager.enable = true;
}
