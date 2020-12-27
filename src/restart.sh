#!/bin/bash
pkill julia; screen ~/julia-a8393c4a3b/bin/julia --project=~/pkg/Project.toml -e "using MemoryHunter, SkyRoom; main(); wait()" &
