#!/bin/bash

github_token=""

function fail() {
 >&2 echo "::error::${@}"
 exit 1
}

for param in "${@}"; do
 case "${param}" in
  '--github-token='*) github_token="${param#*=}";;
  *) fail "Unknown argument '${param}'.";;
 esac
done

if [ ${#github_token} -lt 10 ]; then
 fail "GitHub token (--github-token) is invalid."
fi

echo "- Querying latest Retype release from nuget.org/packages/retypeapp..."
result="$(curl -si https://www.nuget.org/packages/retypeapp)" || \
 fail "Unable to fetch retype package page from nuget.org website."

if [ "$(echo "${result}" | head -n1 | cut -f2 -d" ")" != 200 ]; then
 httpstat="$(echo "${result}" | head -n1 | cut -f2 -d" ")"
 fail "HTTP response ${httpstat} received while trying to query latest Retype Release from NuGet."
fi

latest="$(echo "${result}" | egrep '\| retypeapp ' | sed -E "s/^.*\| retypeapp //" | head -n1 | strings)"

if [ -z "${latest}" ]; then
 fail "Unable to extract latest version number from NuGet website."
elif ! echo "${latest}" | egrep -q '^([0-9]+\.){2}[0-9]+$'; then
 fail "Invalid version number extracted from NuGet website: ${latest}"
fi

major="${latest%%.*}"
majorminor="${latest%.*}"
minor="${majorminor#*.}"
build="${latest##*.}"
latest_re="${latest//\./\\\.}"

echo " Version ${latest}."

echo "- Checking tags..."

overtags=()
if git tag | egrep -q "^v${latest_re}\$"; then
 overtags+=("v${latest}")
fi

if [ "${build}" == 0 ]; then
 if git tag | egrep -q "^v${majorminor}\$"; then
  overtags+=("v${majorminor}")
 fi
fi

if [ ${#overtags[@]} -gt 0 ]; then
 failmsg="Tag"
 if [ ${#overtags[@]} -gt 1 ]; then
  failmsg+="s"
 fi
 pos=0
 beforelastpos=$(( 10#${#overtags[@]} - 2 ))
 for tag in "${overtags[@]}"; do
  failmsg+=" ${overtags[pos]}"
  if [ ${pos} -eq ${beforelastpos} ]; then
   failmsg+=" and"
  elif [ ${pos} -lt ${beforelastpos} ]; then
   failmsg+=","
  fi
  pos="$(( 10#${pos} + 1 ))"
 done

 failmsg+=" already exists. To release this version afresh, remove"
 if [ ${#overtags[@]} -gt 1 ]; then
  failmsg+=" them"
 else
  failmsg+=" it"
 fi
 failmsg+=" from GitHub and try again."

 fail "${failmsg}"
fi

git config user.name "New Release bot"
git config user.email "hello+retypeapp-action-built@object.net"

sed -Ei "s/^(retype_version=\")[^\"]+(\")\$/\1${latest}\2/" build.sh

if ! git status --porcelain | egrep "^ M build\.sh"; then
 # script already points to latest retype version. Check if version tags points to this ref in history

 currsha="$(git log -n1 --pretty='format:%H')"

 outdated_tags=()

 # there's a %(HEAD) format in git command to show an '*' if the major tag matches current checked out
 # ref, but it seems it does not work, so let's not rely on it
 if ! git tag --format='%(objectname)%(refname:strip=2)' | egrep -q "^${currsha}v${major}\$"; then
  outdated_tags+=(":v${major}")
 fi

 if [ ${build} -ne 0 ]; then
  if ! git tag --format='%(objectname)%(refname:strip=2)' | egrep -q "^${currsha}v${majorminor}\$"; then
   outdated_tags+=(":v${majorminor}")
  fi
 fi

 git push origin "${outdated_tags[@]}" || fail "Unable to remove one or more remote tags among: ${outdated_tags[@]#:}"
 git tag -d "${outdated_tags[@]#:}" || fail "Unable to delete one or more local tags among: ${outdated_tags[@]#:}"

 for tag in "${outdated_tags[@]#:}"; do
  git tag "${tag}" || fail "Unable to create tag: ${tag}"
 done
 git tag "v${latest}" || fail "Unable to create tag: v${latest}"
else
 git add build.sh || fail "Unable to stage modified 'build.sh' script for commit."
 git commit -m "Updates Retype reference to version ${latest}." || fail "Unable to commit changes to 'build.sh' script."

 removetags=()
 if git tag | egrep -q "^v${major}\$"; then
  removetags=(":v${major}")
 fi
 if [ ${build} -ne 0 ]; then
  removetags+=(":v${majorminor}")
 fi

 git push origin "${removetags[@]}" || fail "Unable to remove one or more remote tags among: ${removetags[@]#:}"
 git tag -d "${removetags[@]#:}" || fail "Unable to remove one or more local tags among: ${removetags[@]#:}"

 for tag in ${major} ${majorminor} ${latest}; do
  git tag v${tag} || fail "Unable to create tag: v${tag}"
 done
fi