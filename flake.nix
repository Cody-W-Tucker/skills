{
  description = "Curated AI skills exposed as Nix flake data";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # unstable Nixpkgs

  outputs =
    { self, ... }@inputs:

    let
      inherit (inputs.nixpkgs) lib;

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs { inherit system; };
          }
        );

      skillsRoot = ./skills;

      readDirOrEmpty = path: if builtins.pathExists path then builtins.readDir path else { };

      skillDirectory =
        name: type: type == "directory" && builtins.pathExists (skillsRoot + "/${name}/SKILL.md");

      skillFor = name: _: {
        inherit name;
        directory = skillsRoot + "/${name}";
        file = skillsRoot + "/${name}/SKILL.md";
      };

      skillEntries = lib.filterAttrs skillDirectory (readDirOrEmpty skillsRoot);

      skillList = lib.sort (a: b: a.name < b.name) (lib.mapAttrsToList skillFor skillEntries);

      skills = lib.listToAttrs (
        map (skill: {
          name = skill.name;
          value = skill.file;
        }) skillList
      );

    in
    {
      lib = skills // {
        allSkillDirs = map (skill: skill.directory) skillList;
      };

      packages = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = self.packages.${system}.skill;
          skill = pkgs.writeShellApplication {
            name = "skill";
            runtimeInputs = with pkgs; [
              coreutils
              git
              gh
            ];
            text = builtins.readFile ./src/skill.sh;
          };
        }
      );

      apps = forEachSupportedSystem (
        { system, ... }:
        {
          default = self.apps.${system}.skill;
          skill = {
            type = "app";
            program = "${self.packages.${system}.skill}/bin/skill";
            meta.description = "Import curated AI skills from GitHub URLs";
          };
        }
      );

      checks = forEachSupportedSystem (
        { pkgs, ... }:
        {
          skills = pkgs.runCommand "skills-structure-check" { } ''
            SKILLS_ROOT=${./.} ${pkgs.bash}/bin/bash ${./tests/check.sh}
            touch $out
          '';
        }
      );

      formatter = forEachSupportedSystem (
        { pkgs, ... }:
        pkgs.writeShellApplication {
          name = "format-skills-repo";
          runtimeInputs = [ pkgs.nixfmt ];
          text = ''
            if [ "$#" -eq 0 ]; then
              nixfmt flake.nix
            else
              nixfmt "$@"
            fi
          '';
        }
      );

      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              nixfmt
              git
              gh
              self.packages.${system}.skill
            ];

            shellHook = ''
              if [ -d .git ] && [ -f hooks/pre-commit ]; then
                mkdir -p .git/hooks
                ln -sf ../../hooks/pre-commit .git/hooks/pre-commit
              fi
            '';
          };
        }
      );
    };
}
