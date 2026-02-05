{
  description = "VPN Gate client for NetworkManager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      # NixOS module (system-independent)
      nixosModule =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.nm-vpngate;
        in
        {
          options.services.nm-vpngate = {
            enable = lib.mkEnableOption "nm-vpngate VPN Gate client";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.default;
              description = "The nm-vpngate package to use.";
            };

            autoConnect = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable automatic VPN connection via systemd service.";
            };

            retryLimit = lib.mkOption {
              type = lib.types.int;
              default = 5;
              description = "Number of connection retry attempts.";
            };

            settings = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = {
                MODE = "AUTO";
                VPN_TYPE = "OPENVPN";
                TargetCountryShort = "JP|US";
                AUTO_TARGET = "Score";
                AUTO_COND = "MAX";
              };
              description = ''
                Configuration options for nm-vpngate.
                These will be written to /etc/nm-vpngate.conf.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];

            environment.etc."nm-vpngate.conf".text = lib.concatStringsSep "\n" (
              lib.mapAttrsToList (name: value: "${name}=\"${value}\"") cfg.settings
            );

            systemd.services.nm-vpngate = lib.mkIf cfg.autoConnect {
              description = "Automatically connects to a VPN Gate that matches the conditions";
              after = [ "network-online.target" ];
              requires = [ "NetworkManager.service" ];
              wantedBy = [ "network-online.target" ];

              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${cfg.package}/bin/nm-vpngate -a -l ${toString cfg.retryLimit}";
                ExecStop = "${cfg.package}/bin/nm-vpngate --stop";
                ExecStopPost = "${cfg.package}/bin/nm-vpngate --stop";
                Restart = "on-failure";
                RemainAfterExit = true;
              };
            };
          };
        };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        nm-vpngate = pkgs.stdenv.mkDerivation {
          pname = "nm-vpngate";
          version = "unstable-${self.shortRev or "dirty"}";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          buildInputs = [ pkgs.bash ];

          runtimeDeps = with pkgs; [
            curl
            gnugrep
            gnused
            coreutils
            gawk
            networkmanager
          ];

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            install -Dm755 nm-vpngate $out/bin/nm-vpngate
            install -Dm644 nm-vpngate.conf $out/share/nm-vpngate/nm-vpngate.conf

            wrapProgram $out/bin/nm-vpngate \
              --prefix PATH : ${
                pkgs.lib.makeBinPath [
                  pkgs.curl
                  pkgs.gnugrep
                  pkgs.gnused
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.networkmanager
                ]
              }

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "VPN Gate client for NetworkManager";
            homepage = "https://github.com/Hayao0819/nm-vpngate";
            license = licenses.wtfpl;
            platforms = platforms.linux;
            maintainers = [ ];
            mainProgram = "nm-vpngate";
          };
        };
      in
      {
        packages = {
          default = nm-vpngate;
          nm-vpngate = nm-vpngate;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bash
            shellcheck
            shfmt
            curl
            gnugrep
            gnused
            coreutils
          ];

          shellHook = ''
            echo "nm-vpngate development environment loaded!"
            echo "Run 'shellcheck nm-vpngate' to lint the script"
            echo "Run 'shfmt -d nm-vpngate' to check formatting"
          '';
        };
      }
    )
    // {
      # System-independent outputs
      nixosModules.default = nixosModule;
      nixosModules.nm-vpngate = nixosModule;
    };
}
