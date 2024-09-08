{ config
, lib
, pkgs
, ...
}:

with lib;

let
  cfg = config.services.github-actions-runners;
in
{
  imports = [ ./options.nix ];

  config = {
    systemd.services = flip mapAttrs' config.services.github-actions-runners (name: cfg:
      let
        svcName = "github-actions-runner-${name}";
        systemdDir = "github-actions-runners/${name}";
      in
      nameValuePair svcName {
        description = "github-actions-runner service template";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network.target" "network-online.target" ];

        environment =
          let
            root = "/var/lib/github-actions-runners/${name}";
          in
          {
            # lmao I think github-runner writes to HOME/.runner
            HOME = root;
            RUNNER_ROOT = root;
          };

        path = (with pkgs; [
          bash
          coreutils
          git
          gnutar
          gzip
        ]) ++ [
          config.nix.package
        ] ++ cfg.extraPackages;

        serviceConfig = {
          RuntimeDirectory = [ "github-actions-runners/${name}" ];
          WorkingDirectory = "/var/lib/github-actions-runners/${name}";
          LogsDirectory = [ "github-actions-runners/${name}" ];
          StateDirectory = [ "github-actions-runners/${name}" ];

          ExecStart = "${pkgs.github-runner}/bin/Runner.Listener run --startuptype service";
          ExecStartPre = (pkgs.writeShellScript "pre" ''
            set -x
            set -euo pipefail
            
            mkdir -p "$STATE_DIRECTORY/work"

            token="$(<${escapeShellArg cfg.tokenFile})"

            args=(
              --unattended
              --disableupdate
              --work "$STATE_DIRECTORY/work"
              --url ${escapeShellArg cfg.url}
              --labels ${escapeShellArg (concatStringsSep "," cfg.extraLabels)}
              --pat "$token"
              ${optionalString (name != null ) "--name ${escapeShellArg name}"}
              ${optionalString cfg.replace "--replace"}
              ${optionalString (cfg.runnerGroup != null) "--runnergroup ${escapeShellArg cfg.runnerGroup}"}
              ${optionalString cfg.ephemeral "--ephemeral"}
              ${optionalString cfg.noDefaultLabels "--no-default-labels"}
            )

            # clear runner state, except its work dir
            echo "_______________BEFORE111"
            ${pkgs.eza}/bin/eza --tree --level 3 -al $STATE_DIRECTORY/
            echo "_______________BEFORE"
            find "$STATE_DIRECTORY/" -mindepth 1 \
              -not -path "$STATE_DIRECTORY/work*" \
              -not -path "$STATE_DIRECTORY/.cache*" \
              -delete
            echo "_______________AFTER"
            ${pkgs.eza}/bin/eza --tree --level 3 -al $STATE_DIRECTORY/
            
            ${cfg.package}/bin/Runner.Listener configure "''${args[@]}"
          '');

          # fuckin systemd
          # Restart = "always";

          # give it 45s to count up failures, since it takes a while to fail
          DefaultStartLimitIntervalSec = "120s";

          KillSignal = "SIGINT";
        };
      }
    );
  };
}
