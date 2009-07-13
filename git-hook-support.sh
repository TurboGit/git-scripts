
# Tools

STYLECHECKER=style_checker
PYTHON=/usr/bin/python

TRACENV=/home/trac/rootenv
TRACURL=http://localhost:8000

# Path needed by some tools (style_checker)

PATH=/opt/gnat/bin:/opt/bin:/usr/bin:/bin:/usr/local/bin:$PATH
export PATH

# Style Check all files for a specific transaction

root=$(mktemp -d /tmp/git-update-hook-XXXXXX)
log=$root/log
tree=$root/diff-tree
frem=$root/files-removed
fadd=$root/files-added
fman=$root/manifest

# Set Style_Checker options

OWEB="-H -cP -cY -l256"

#  The copyright pattern to check
CPYR=""

#  Pathnames matching the regexp will be excluded from the test
EXCLUDE=""

SC_OPTS="-H -ign out -ign tmplt -ign sed -ign txt \
        -lang Ada -H -cP -cY -sp -gnat05 -lang TXML $OWEB \
        -lang XML $OWEB -lang HTML $OWEB -lang XSD $OWEB -lang CSS $OWEB"

# To be set with the name of the MANIFEST file if any, this script will check
# if an added or removed file is properly added or removed from MANIFEST.
MANIFEST=""

# Process each file

check_file() {
   id=$2
   file=`basename $4`
   mode=$(echo $3 | cut -c1)

   #  Check if it is a file to ignore

   if [[ -n "$EXCLUDE" && `echo "$6" | grep --regexp="$EXCLUDE"` ]]; then
      return 0;
   fi

   #  skip deleted/renamed files

   if [[ "$mode" = "D" || "$mode" = "R" ]]; then
       echo $4 >> $frem
       return 0;
   fi

   git show $id > $root/$file

   #  If the MANIFEST keep it around

   if [[ "$4" = "$MANIFEST" ]]; then
       cp $root/$file $fman
   fi

   #  If a new file, record it

   if [[ "$mode" == "A" ]]; then
       echo $4 >> $fadd
   fi

   (cd $root; $STYLECHECKER $SC_OPTS -n "$4" "$file" )
   res=$?
   rm -f $root/$file
   return $res
}

# Process the changeset

check_style()
{
    oldrev=$1
    newrev=$2

    git diff-tree -r "$oldrev" "$newrev" > $tree

    exit_status=0

    while read old_mode new_mode old_sha1 new_sha1 status name; do
        check_file $old_sha1 $new_sha1 $status $name 2>&1 >> $log
        if [[ $? != 0 ]]; then
	    echo
	    cat $log >&2
	    echo -e "For details run: git diff ${old_sha1:0:7} ${new_sha1:0:7}" >&2
	    echo
	    exit_status=1
        fi
    done < $tree

    #  Check for MANIFEST if needed

    if [[ -n "$MANIFEST" && -f $fadd ]]; then
	if [[ ! -f $fman ]]; then
	    echo ""
	    echo Files added, but $MANIFEST not updated, consider adding:
	    git diff-tree --name-only --diff-filter=A -r $oldrev $newrev
	    exit_status=1
	else
	    while read fadded
	    do
		grep --quiet "$fadded\$" $fman
		if [[ $? = 1 ]]; then
		    echo File $fadded added but missing in $MANIFEST
		    exit_status=1
		fi
	    done < $fadd
	fi
    fi

    if [[ -n "$MANIFEST" && -f $frem ]]; then
	if [[ ! -f $fman ]]; then
	    echo ""
	    echo Files removed, but $MANIFEST not updated, condider removing:
	    git diff-tree --name-only --diff-filter=D -r $oldrev $newrev
	    exit_status=1
	else
	    while read fremoved
	    do
		grep --quiet "$fremoved\$" $fman
		if [[ $? = 0 ]]; then
		    echo File $fremoved removed but still in $MANIFEST
		    exit_status=1
		fi
	    done < $frem
	fi
    fi

    rm -fr $root

    # --- Finished
    return $exit_status
}

# Clean tmp directory

clean_temp() {
    rm -fr $root
}

# Check log not empty

function log_not_empty() {
   REV="$1"

   RES=$(git log -1 --pretty="%s%n%b" $REV | grep "[a-zA-Z0-9]")

   if [ "$RES" = "" ]; then
      echo "Won't commit with an empty log message." 1>&2
      return 1;
   fi

   return 0;
}

# Post receive action to log message in Trac

function trac_post_receive_record_log() {
    oldrev=$1
    newrev=$2
    ref=$3
    MODULE="$4"

    if expr "$oldrev" : "0*$" >/dev/null
    then
	git-rev-list "$newrev"
    else
	git-rev-list "$newrev" "^$oldrev"
    fi | tac | while read csha ; do
	AUTHOR="$(git-rev-list -n 1 $csha --pretty=format:%an | sed '1d')"
	LOG="$(git-rev-list -n 1 $csha --pretty=medium | sed '1,3d;s:^    ::')"
   
	$PYTHON /home/git/scripts/trac-post-commit-hook \
	    -p "${TRACENV}/$MODULE"  \
	    -r "$csha"      \
	    -u "$AUTHOR"    \
	    -m "$LOG"       \
	    -s "${TRACURL}/$MODULE" 2> /tmp/post_commit_err_$csha
    done
}

# Pre update action to check for proper ticket

function trac_update_check_log() {
    oldrev=$1
    newrev=$2
    MODULE="$3"

    for csha in $(git-rev-list $oldrev..$newrev); do
	LOG="$(git-rev-list -n 1 $csha --pretty=medium | sed '1,3d;s:^    ::')"

	$PYTHON /home/git/scripts/trac-pre-commit-hook \
	    "$TRACENV/$MODULE" "$LOG" || return 1
    done;

    return 0;
}

# Post commit send mail
# Can be called with $4 = "--diff n" to skip log diff in e-mail

function send_mail_post_receive() {
    oldrev=$1
    newrev=$2
    ref=$3
    MODULE="$4"

    git log -p $oldrev..$newrev > $log
    cat $log | mail -s "[$MODULE] $ref $oldrev..$newrev" $5 $6 $7 $8 $9
    rm -fr $root
}

# Post commit send xmpp

function send_xmpp_post_commit() {
    REPOS="$1"
    REV="$2"
    SUBJECT=$3
    XMPPRC=$4

    AUTHOR=$(git log -1 --pretty="%an")
    LOG=$(git log -1 --pretty="%s%n%b")

    echo $AUTHOR $LOG | sendxmpp -f $XMPPRC -s $SUBJECT $5 $6 $7
}
