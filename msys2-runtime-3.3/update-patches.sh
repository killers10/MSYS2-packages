#!/bin/sh

die () {
	echo "$*" >&2
	exit 1
}

cd "$(dirname "$0")" ||
die "Could not cd to msys2-runtime/"

git rev-parse --verify HEAD >/dev/null &&
git update-index -q --ignore-submodules --refresh &&
git diff-files --quiet --ignore-submodules &&
git diff-index --cached --quiet --ignore-submodules HEAD -- ||
die "Clean worktree required"

git rm 0*.patch ||
die "Could not remove previous patches"

base_tag=refs/tags/cygwin-"$(sed -ne 'y/./_/' -e 's/^pkgver=//p' <PKGBUILD)"-release
source_url=$(sed -ne 's/^source=\([^:]\+::\)\?["'\'']\?\([^"'\''#?=&,;[:space:]]\+[^)"'\''#?=&,;[:space:]]\).*/\2/p' <PKGBUILD)

git -C src/msys2-runtime fetch --no-tags "$source_url" "$base_tag:$base_tag"

merging_rebase_start="$(git -C src/msys2-runtime \
    rev-parse --verify --quiet HEAD^{/Start.the.merging.rebase})"

git -c core.abbrev=7 \
	-c diff.renames=true \
	-c format.from=false \
	-c format.numbered=auto \
	-c format.useAutoBase=false \
	-C src/msys2-runtime \
	format-patch \
		--no-signature \
		--topo-order \
		--diff-algorithm=default \
		--no-attach \
		--no-add-header \
		--no-cover-letter \
		--no-thread \
		--suffix=.patch \
		--subject-prefix=PATCH \
		--output-directory ../.. \
		$base_tag.. ${merging_rebase_start:+^$merging_rebase_start} \
		-- ':(exclude).github/' ||
die "Could not generate new patch set"

patches="$(ls 0*.patch)" &&
for p in $patches
do
	sed -i 's/^\(Subject: \[PATCH [0-9]*\/\)[1-9][0-9]*/\1N/' $p ||
	die "Could not fix Subject: line in $p"
done &&
git -C src/msys2-runtime rev-parse --verify HEAD >msys2-runtime.commit &&
git add $patches msys2-runtime.commit ||
die "Could not stage new patch set"

in_sources="$(echo "$patches" | sed "{s/^/        /;:1;N;s/\\n/\\\\n        /;b1}")"
in_prepare="$(echo "$patches" |
	sed "{s|^|  git am --committer-date-is-author-date --ignore-space-change \"\${srcdir}\"/|;:1;N;
	 s|\\n|\\\\n  git am --committer-date-is-author-date --ignore-space-change \"\${srcdir}\"/|;b1}")"
sed -i -e "/^        0.*\.patch$/{:1;N;/[^)]$/b1;s|.*|$in_sources)|}" \
	-e "/^  git am.*\.patch$/{:2;N;/[^}]$/b2;s|.*|$in_prepare\\n\\}|}" \
	PKGBUILD ||
die "Could not update the patch set in PKGBUILD"

if git rev-parse --verify HEAD >/dev/null &&
	git update-index -q --ignore-submodules --refresh &&
	git diff-files --quiet --ignore-submodules &&
	git diff-index --cached --quiet --ignore-submodules HEAD --
then
	echo "Already up to date!" >&2
	exit 0
fi

updpkgsums ||
die "Could not update the patch set checksums in PKGBUILD"

# bump pkgrel
if ! git diff @{u} -- PKGBUILD | grep -q '^+pkgver'
then
	pkgrel=$((1+$(sed -n -e 's/^pkgrel=//p' <PKGBUILD))) &&
	sed -i -e "s/^\(pkgrel=\).*/\1$pkgrel/" PKGBUILD ||
	die "Could not increment pkgrel"
fi

git add PKGBUILD ||
die "Could not stage updates in PKGBUILD"
