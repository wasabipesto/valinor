# HOMEMADE RESTIC UTIL
# PART 1: BACK IT UP

# ADD TO CRON:
#  xyzzy
# RUN ON EVERY MACHINE

source .env

restic backup /home /opt

# TODO:
# - set up cron schedules
# - set up proper database backups
# - set up notifications (discord)