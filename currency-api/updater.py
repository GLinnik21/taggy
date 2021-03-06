#!env/bin/python
from app import db, models
import urllib2
import simplejson
import datetime

APP_ID = "40639356d56148f1ae26348d670e889f"

def main():
    print 'Updating rates...'
    request = urllib2.Request("http://openexchangerates.org/api/latest.json?app_id=%s" % (APP_ID))
    opener = urllib2.build_opener()
    f = opener.open(request)
    result = simplejson.load(f)
    rates = result['rates']

    date = datetime.datetime.fromtimestamp(int(result['timestamp']))
    lastRate = models.Rate.query.order_by(models.Rate.date.desc()).first()

    if not lastRate or lastRate.date != date:
        for rate in rates:
            dbrate = models.Rate(name=rate, date=date, value=rates[rate])
            db.session.add(dbrate)
            print rate,
        db.session.commit()
    else:
        print 'Currency is up to date'

if __name__ == '__main__':
    main()
