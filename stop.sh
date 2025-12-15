#!/bin/bash

# Stop the container
docker stop mailcheck

# Remove the container
docker rm mailcheck

echo "MailCheck stopped"
