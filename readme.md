# Image Server Cantaloupe

A single Docker file that builds and runs [Cantaloupe](https://cantaloupe-project.github.io/) image server.

## Configuration

There is a single entrypoint, [entrypoint/entrypoint.sh](entrypoint/entrypoint.sh). Optional steps only run when the matching envvar is set, so no command override is needed:

| Envvars set                          | Behaviour                                                                           |
| ------------------------------------ | ----------------------------------------------------------------------------------- |
| _(none)_                             | Runs using the bundled [cantaloupe.properties.sample](cantaloupe.properties.sample) |
| `PROPERTIES_LOCATION`                | Downloads the properties file from S3 and runs using it                             |
| `KAKADU_LOCATION` + `KAKADU_VERSION` | Also downloads and installs the Kakadu binaries                                     |

> [!TIP]
> The `/opt/app/s3-config.sh` and `/opt/app/kakadu.sh` commands still work and are kept so existing
> task definitions don't break, but they now just delegate to the entrypoint.

### Default

The default command runs Cantaloupe using [cantaloupe.properties.sample](cantaloupe.properties.sample).

This sample file is copied from the Cantaloupe repo with the following changes:

```ini
# Use ManualSelectionStrategy as AutomaticSelectionStrategy will always try and use Kakadu, 
# see Cantaloupe https://github.com/cantaloupe-project/cantaloupe/issues/559
processor.selection_strategy = ManualSelectionStrategy

# Use OpenJpegProcessor for handling jp2 files
processor.ManualSelectionStrategy.jp2 = OpenJpegProcessor
```

> Using OpenJpeg allows running without any changes.

### S3 Sourced Properties

Set `PROPERTIES_LOCATION` env var to a valid S3 location containing a cantaloupe properties file and use `/opt/app/entrypoint.sh` command. This will download the properties file and launch cantaloupe using it.

### Kakadu Native Processor

Set `KAKADU_LOCATION` env var to a valid S3 location containing Kakadu binaries and `KAKADU_VERSION` to the version of Kakadu being used. Use `/opt/app/entrypoint.sh` command. 

This will download and extract the Kakadu binaries to appropriate location for cantaloupe.

> [!TIP]
> Remember to set `AutomaticSelectionStrategy` to use Kakadu, see (default)[#default] above.
>
> `entrypoint.sh` copies libraries into `/usr/lib`, so it must run as root (`--user root`). The image otherwise runs as the unprivileged `cantaloupe` user.

#### Kakadu Archive

It's expected that the Kakadu archive is a `tar.gz` with the following structure:

```
kakadu-<version>/
  lib/
  bin/
  <etc>/
java/
  kdu_jni/
  kdu_jni.jar
```

### Handling Multiple S3 bucket sources

When using an [S3Source](https://cantaloupe-project.github.io/manual/5.0/sources.html#S3Source) a single bucket is supported via the `S3Source.BasicLookupStrategy.bucket.name` property.

To support multiple buckets, the included `delegates.rb` file handles the `s3source_object_info` delegate. This parses the incoming identifier and pulls bucket and key from it. It handles the following formats:

* `s3://{region}/{bucket}/{key}`
* `s3://{bucket}/{key}`

A sample request would then be: `http://cantaloupe/iiif/3/s3:%2f%2fmy-bucket%2f2my-key/full/max/0/default.jpg`.

```ini
delegate_script.enabled = true
source.static = S3Source
S3Source.lookup_strategy = ScriptLookupStrategy
```

## Running Locally

The dockerfile can be run locally, or run via the sample docker-compose file.

This runs on port 8182 and by default will look in `/home/cantaloupe/images/` for image sources.

```bash
# build docker file
docker build -t dlcs-cantaloupe:local .

# run docker file, enabling /admin
docker run --rm -it -p 8182:8182 \
    -e ENDPOINT_ADMIN_ENABLED=true \
    -e ENDPOINT_ADMIN_SECRET=admin \
    -v path/to/images:/home/cantaloupe/images/ \
    --name dlcs-cantaloupe \
    dlcs-cantaloupe:local

# use cantaloupe properties file stored in s3
docker run --rm -it -p 8182:8182 \
    -e ENDPOINT_ADMIN_ENABLED=true \
    -e ENDPOINT_ADMIN_SECRET=admin \
    -e PROPERTIES_LOCATION=s3://my-bucket-name/cantaloupe.properties.s3 \
    -v path/to/images:/home/cantaloupe/images/ \
    --name dlcs-cantaloupe \
    dlcs-cantaloupe:local \
    /opt/app/s3-config.sh

# use cantaloupe properties file stored in s3 and Kakadu binaries
docker run --rm -it -p 8182:8182 \
    -e ENDPOINT_ADMIN_ENABLED=true \
    -e ENDPOINT_ADMIN_SECRET=admin \
    -e PROPERTIES_LOCATION=s3://my-bucket-name/cantaloupe.properties.s3 \
    -e KAKADU_LOCATION=s3://my-bucket-name/kakadu-8.2.1.tar.gz \
    -e KAKADU_VERSION=8.2.1 \
    -v path/to/images:/home/cantaloupe/images/ \
    --name dlcs-cantaloupe \
    dlcs-cantaloupe:local \
    /opt/app/kakadu.sh

# run as "special-server" using S3Source
docker run --rm -it -p 8182:8182 \
    -e ENDPOINT_ADMIN_ENABLED=true \
    -e ENDPOINT_ADMIN_SECRET=admin \
    -e DELEGATE_SCRIPT_ENABLED=true \
    -e SOURCE_STATIC=S3Source \
    -e S3SOURCE_LOOKUP_STRATEGY=ScriptLookupStrategy \
    --name dlcs-cantaloupe \
    dlcs-cantaloupe:local
```

Alternatively there's a docker compose file to run, copy `.env.dist` -> `.env` and alter as required.

```bash
# Run docker-compose
docker compose up
```

## Processors

By default it will run with Cantaloupe v5.0.7 running the following [processors](https://cantaloupe-project.github.io/manual/5.0/processors.html):

* Ffmpeg
* Grok (v20.4.0)
* Jai
* Java2d
* OpenJpeg (v2.5.4)
* PdfBox
* TurboJpeg

### Kakadu

Kakadu native processor is supported by providing path to Kakadu (see [above](#kakadu-native-processor))

### Dependencies

libturbojpeg comes from Ubuntu's `libturbojpeg` package. Cantaloupe bundles the TurboJPEG Java binding but not the native library, and its `TJLoader` looks for it at a hardcoded path, so the Dockerfile symlinks the packaged library into `/opt/libjpeg-turbo/lib/libturbojpeg.so`.

## Java Memory 

The image uses Ubuntu Noble + OpenJDK 21, and defaults Java heap to initial 256MB/max 2GB in the Dockerfile.

These can be overridden by specifying the following envvars (see https://cantaloupe-project.github.io/manual/5.0/deployment.html#MemoryHeapMemory):

* MAXHEAP - Value for `-Xmx` Java arg.
* INITHEAP - Value for `-Xms` Java arg.
* JAVA_OPTS - Any extra JVM flags, appended after `-Xms`/`-Xmx`.

Setting `MAXHEAP`/`INITHEAP` to an empty string omits that flag entirely, which lets the JVM size
the heap from the container limit instead of a fixed value:

```bash
docker run --rm -it -p 8182:8182 \
    -e MAXHEAP= -e INITHEAP= \
    -e JAVA_OPTS=-XX:MaxRAMPercentage=75 \
    dlcs-cantaloupe:local
```

e.g.

```bash
docker run --rm -it -p 8182:8182 \
    -e ENDPOINT_ADMIN_ENABLED=true \
    -e ENDPOINT_ADMIN_SECRET=admin \
    -e MAXHEAP=5g \
    -e INITHEAP=3g \
    -v path/to/images:/home/cantaloupe/images/ \
    --name dlcs-cantaloupe \
    dlcs-cantaloupe:local
```

## Github Actions

Basic github action will build images:
* On PR to `main`, tagged with `pr-xxx` and sha1.
* On workflow_dispatch. Tagged with sha1 and tagged with Cantaloupe version if run against `main` branch.
  
> [!IMPORTANT]
> The Cantaloupe version is hardcoded in [build-image.yml](./.github/workflows/build-image.yml).

## New Build Checklist

Whenever we build a new image:
* Update the hardcoded Cantaloupe version in [build-image.yml](./.github/workflows/build-image.yml)
* Update default [processor](#processors) versions, above.
* Verify that all processors are working.

Test all processors working, see [test/smoke-test.sh](./test/smoke-test.sh) for example.

> [!CAUTION]
> The above doesn't test KakaduNativeProcessor as that requires a license.