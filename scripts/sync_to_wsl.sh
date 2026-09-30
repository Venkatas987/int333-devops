#!/usr/bin/env bash
mkdir -p ~/int333_check
rsync -a --delete --exclude node_modules --exclude .git /mnt/d/projects/int333/ ~/int333_check/
echo "Sync complete: D:\projects\int333 -> ~/int333_check"
