# SPDX-FileCopyrightText: 2021-2022 Noah Fontes
#
# SPDX-License-Identifier: Apache-2.0

{ lib, ... }: with lib;
{
  # Construct an &&-separated list for each of the commands given.
  mkShellAndIfList = cmds: let
    wrapCmd = cmd: ''{
      ${cmd}
    }'';
    maybeWrapCmd = cmd: if hasInfix "\n" cmd then wrapCmd cmd else cmd;
    wrappedCmds = map maybeWrapCmd cmds;
  in concatStringsSep " \\\n  && " wrappedCmds;
}
