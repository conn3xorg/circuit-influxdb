# Local example

Applies circuit-influxdb to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

InfluxDB's systemd unit runs it in a sandbox, which systemd can only set up in a privileged container, so the host container runs privileged. That's simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
export TF_VAR_admin_token="apiv3_$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=')"
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` To write a point and read it back on the container:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1 \
  "curl -s -H 'Authorization: Bearer $TF_VAR_admin_token' 'http://127.0.0.1:8181/api/v3/write_lp?db=demo' --data-binary 'cpu,host=box usage=42.5' &&
   curl -s -H 'Authorization: Bearer $TF_VAR_admin_token' 'http://127.0.0.1:8181/api/v3/query_sql?db=demo&q=SELECT+*+FROM+cpu'"
```

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINER_NAME` to run more than one, and `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
