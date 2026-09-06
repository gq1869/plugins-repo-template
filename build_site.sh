#!/bin/bash
# AGPLv3.0
# https://github.com/stashapp/CommunityScripts/blob/main/LICENSE

# builds a repository of plugins
# outputs to _site with the following structure:
# index.yml
# <plugin_id>.zip
# Each zip file contains the plugin.yml file and any other files in the same directory

outdir="$1"
if [ -z "$outdir" ]; then
    outdir="_site"
fi

rm -rf "$outdir"
mkdir -p "$outdir"

buildPlugin() 
{
    f=$1
    # get the plugin id from the directory
    dir=$(dirname "$f")
    plugin_id=$(basename "$f" .yml)

    echo "Processing $plugin_id"

    # create a directory for the version
    version=$(git log -n 1 --pretty=format:%h -- "$dir"/*)
    updated=$(TZ=UTC0 git log -n 1 --date="format-local:%F %T" --pretty=format:%ad -- "$dir"/*)
    
    # create the zip file
    # copy other files
    zipfile=$(realpath "$outdir/$plugin_id.zip")
    rm -f "$zipfile"

    pushd "$dir" > /dev/null
    zip -r "$zipfile" . > /dev/null
    popd > /dev/null

    name=$(grep "^name:" "$f" | head -n 1 | cut -d' ' -f2- | sed -e 's/\r//' -e 's/^"\(.*\)"$/\1/')
    description=$(grep "^description:" "$f" | head -n 1 | cut -d' ' -f2- | sed -e 's/\r//' -e 's/^"\(.*\)"$/\1/')
    ymlVersion=$(grep "^version:" "$f" | head -n 1 | cut -d' ' -f2- | sed -e 's/\r//' -e 's/^"\(.*\)"$/\1/')
    version="$ymlVersion-$version"
    IFS=$'\n' dep=$(grep "^# requires:" "$f" | cut -c 12- | sed -e 's/\r//')

    # write to spec index
    echo "- id: $plugin_id
  name: $name
  metadata:
    description: $description
  version: $version
  date: $updated
  path: $plugin_id.zip
  sha256: $(sha256sum "$zipfile" | cut -d' ' -f1)" >> "$outdir"/index.yml

    # handle dependencies
    if [ ! -z "$dep" ]; then
        echo "  requires:" >> "$outdir"/index.yml
        for d in ${dep//,/ }; do
            echo "    - $d" >> "$outdir"/index.yml
        done
    fi

    echo "" >> "$outdir"/index.yml
}

# restrict to the plugins/<dir>/<id>.yml shape: this excludes ymls nested
# deeper (vendored deps, i18n files) and ymls sitting directly in plugins/
# (which would otherwise zip the entire plugins/ tree as one "plugin")
dupes=$(find ./plugins -mindepth 2 -maxdepth 2 -name '*.yml' -print0 \
        | xargs -0 -r -n1 basename | sed 's/\.yml$//' | sort | uniq -d)
if [ -n "$dupes" ]; then
    echo "error: duplicate plugin ids (same yml filename in different directories): $dupes" >&2
    exit 1
fi

while IFS= read -r -d '' file; do
    buildPlugin "$file"
done < <(find ./plugins -mindepth 2 -maxdepth 2 -name '*.yml' -print0)
