#!/bin/sh

mkdir /tmp/mailExtraction
cd /tmp/mailExtraction

MBOX_FILE="${1}/mbox"

# Split the mbox file into individual messages
mkdir tmp
awk 'BEGIN{chunk=0} /^From /{msgs++;if(msgs==1){msgs=0;chunk++}}{print > "tmp/chunk_" chunk ".txt"}' ${MBOX_FILE}

# Iterate with spamassassin over each of them
MAIL_COUNT=$(find tmp -type f | wc -l)
SPAM=0
HAM=0
PROCESSED=0
for f in tmp/chunk_*.txt; do
	/usr/bin/progress $PROCESSED $MAIL_COUNT

	spamassassin --mbox -e $f >/dev/null

	if [ "$?" -eq "0" ]; then
		HAM=$((HAM+1))
	else
		SPAM=$((SPAM+1))
	fi

	PROCESSED=$((PROCESSED+1))
done

echo "{ \"total\": $MAIL_COUNT, \"spam\": $SPAM, \"ham\": $HAM }"
