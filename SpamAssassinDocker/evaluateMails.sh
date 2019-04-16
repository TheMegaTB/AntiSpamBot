#!/bin/sh
docker run --rm -v /tmp/mails/AntiSpamBot/Evaluation:/mails sa /mails/Spam.mbox >/tmp/out.json
