#!/bin/bash

set -eu -o pipefail

repo_root=$(dirname $(cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd))

pushd $repo_root/toc/working-groups >/dev/null

for group in $(ls ../*.md | grep -v -e ROLES -e CHANGEPLAN -e PRINCIPLES -e GOVERNANCE); do
    cat ${group} | awk '/^```yaml$/{flag=1;next}/^```$/{flag=0}flag' | \
        ruby -rjson -ryaml -e "puts YAML.load(ARGF.read).to_json" 2> /dev/null | jq '[.]'
done

for working_group in $(ls *.md | grep -v -e WORKING-GROUPS -e paketo -e vulnerability -e concourse); do
      cat ${working_group} | awk '/^```yaml$/{flag=1;next}/^```$/{flag=0}flag' | \
            ruby -rjson -ryaml -e "puts YAML.load(ARGF.read).to_json" 2> /dev/null | jq '[.]'
done

