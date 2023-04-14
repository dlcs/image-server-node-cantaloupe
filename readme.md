# Image Server Cantaloupe

A single Docker file that builds and runs [Cantaloupe](https://cantaloupe-project.github.io/) image server.

## Configuration

There are 3 different commands for running:

### Default

The default command runs Cantaloupe using [cantaloupe.properties.sample](cantaloupe.properties.sample).

This sample file is copied from the Cantaloupe repo with the following changes:

```ini
# Use ManualSelectionStrategy as AutomaticSelectionStrategy will always try and use Kakadu, 
# see Cantaloupe https://github.com/cantaloupe-project/cantaloupe/issues/559
processor.selection_strategy = ManualSelectionStrategy

# Use GrokProcessor for handling jp2 files
processor.ManualSelectionStrategy.jp2 = GrokProcessor
```

> Grok is favoured over OpenJpeg as the latter isn't correctly handling ICC profiles

### S3 Sourced Properties

Set `PROPERTIES_LOCATION` env var to a valid S3 location containing a cantaloupe properties file and use `/opt/app/s3-config.sh` command. This will download the properties file and launch cantaloupe using it.

### Kakadu Native Processor

Set `KAKADU_LOCATION` env var to a valid S3 location containing Kakadu binaries and `KAKADU_VERSION` to the version of Kakadu being used. Use `/opt/app/kakadu.sh` command. 

This will download and extract the Kakadu binaries to appropriate location for cantaloupe.

Also need to set `PROPERTIES_LOCATION` as above as it's expected that config will be loaded from S3.

> Remember to set `AutomaticSelectionStrategy` to use Kakadu, see (default)[#default] above.

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

By default it will run with Cantaloupe running the following [processors](https://cantaloupe-project.github.io/manual/5.0/processors.html):

* Ffmpeg
* Grok
* Jai
* Java2d
* OpenJpeg (v2.5.0)
* PdfBox
* TurboJpeg

### Kakadu

Kakadu native processor is supported by providing path to Kakadu (see [above](#kakadu-native-processor))

### Dependencies

libjpeg dep is copied from the official [cantaloupe repo](https://github.com/cantaloupe-project/cantaloupe/tree/develop/docker/Linux-JDK11/image_files/libjpeg-turbo/lib64).

## Java Memory 

The initial heap and maximum heap size are defaulted to 2GB in the Dockerfile.

These can be overridden by specifying the following envvars (see https://cantaloupe-project.github.io/manual/5.0/deployment.html#MemoryHeapMemory):

* MAXHEAP - Value for `-Xmx` Java arg.
* INITHEAP - Value for `-Xms` Java arg.

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