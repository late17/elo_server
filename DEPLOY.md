# Deploying to the server

Server: `root@51.15.63.150`, app dir `/srv/elodebate`, service `elo_server`.

## Standard deploy (code changes)

1. **Commit and push your changes locally**
   ```
   git add .
   git commit -m "..."
   git push
   ```

2. **SSH into the server**
   ```
   ssh root@51.15.63.150
   ```

3. **Pull and build on the server**
   ```
   cd /srv/elodebate
   git pull
   MIX_ENV=prod mix deps.get --only prod
   MIX_ENV=prod mix assets.deploy
   MIX_ENV=prod mix release --overwrite
   ```

4. **Restart the service**
   ```
   sudo systemctl restart elo_server
   ```

5. **Check it came up cleanly**
   ```
   sudo journalctl -fu elo_server
   ```
   (Ctrl+C to stop tailing once you see it's healthy.)

## If a migration is involved

Run migrations as part of the release before/after restart, per your project's normal migration command (e.g. `_build/prod/rel/elo_server/bin/elo_server eval "EloServer.Release.migrate"` if you have a Release module — adjust to whatever migration task this project uses). Confirm this step against your `lib/elo_server/release.ex` if present, since it wasn't specified in your original instructions.

## Rollback if something breaks

```
cd /srv/elodebate
git log --oneline -5        # find the last good commit
git checkout <good-commit>
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
sudo systemctl restart elo_server
```

## Reference: other server ops

**Restart only (no code change)**
```
sudo systemctl restart elo_server
```

**View logs**
```
sudo journalctl -fu elo_server
```

**Dump DB (on server)**
```
sudo -u postgres pg_dump -Fc elodebate_prod > /tmp/elo_dump.dump
```

**Restore DB (on server)**
```
sudo -u postgres psql -d elodebate_prod -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public AUTHORIZATION elodebate;"
sudo -u postgres pg_restore --no-owner --role=elodebate -d elodebate_prod /tmp/elo_dump.dump
sudo systemctl restart elo_server
```

**Download DB dump to local machine**
```
scp root@51.15.63.150:/tmp/elo_dump.dump ~/Downloads/elo_dump.dump
```

**Upload DB dump from local machine**
```
scp ~/Downloads/elo_dump.dump root@51.15.63.150:/tmp/elo_dump.dump
```
