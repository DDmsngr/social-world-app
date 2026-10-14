import json, sys, urllib.parse, urllib.request, re
UA = {'User-Agent': 'ChaWoEditorial/1.0 (https://deepdrift.tech; editorial@chawo)'}
def get(url):
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30))
def article(title, sentences=12):
    q = urllib.parse.urlencode({'action':'query','format':'json','prop':'extracts|pageimages|info','explaintext':1,'titles':title,'piprop':'original','inprop':'url','redirects':1})
    d = get('https://ru.wikipedia.org/w/api.php?' + q)
    page = next(iter(d['query']['pages'].values()))
    return page
def image_info(filename):
    q = urllib.parse.urlencode({'action':'query','format':'json','prop':'imageinfo','iiprop':'url|extmetadata|size','iiurlwidth':1280,'titles':'File:'+filename})
    d = get('https://commons.wikimedia.org/w/api.php?' + q)
    page = next(iter(d['query']['pages'].values()))
    ii = page['imageinfo'][0]; m = ii['extmetadata']
    strip = lambda s: re.sub('<[^>]+>','',s or '').strip()
    return {'thumb': ii['thumburl'], 'page': ii['descriptionurl'], 'artist': strip(m.get('Artist',{}).get('value')), 'license': strip(m.get('LicenseShortName',{}).get('value')), 'size': (ii['width'], ii['height'])}
if __name__ == '__main__':
    p = article(sys.argv[1])
    print(p['fullurl']); print((p.get('original') or {}).get('source'))
    print(p['extract'][:int(sys.argv[2]) if len(sys.argv)>2 else 3500])
