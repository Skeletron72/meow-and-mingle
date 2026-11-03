"""Замеры интерфейса по пикселям: python3 tools/measure_ui.py <папка со скриншотами> m_city.png m_menu.png ...
Для кнопок проверяет воздух сверху и снизу вокруг текста, для подписей — поля до краёв плашки (>= 3 px), печатает воздух деревянных страниц."""
import sys, json, glob, os
from PIL import Image
S=sys.argv[1].rstrip('/')+'/'
SC=2
def near(c, t, tol=22): return all(abs(c[i]-t[i])<=tol for i in range(3))
def hexc(h): return tuple(int(h[i:i+2],16) for i in (0,2,4))
def bbox(im, rect, colors, tol=22):
    x0,y0,x1,y1=[int(round(v*SC)) for v in (rect[0],rect[1],rect[0]+rect[2],rect[1]+rect[3])]
    x0=max(0,x0);y0=max(0,y0);x1=min(im.width,x1);y1=min(im.height,y1)
    xs=[];ys=[]
    px=im.load()
    for y in range(y0,y1):
        for x in range(x0,x1):
            c=px[x,y][:3]
            if any(near(c,t,tol) for t in colors):
                xs.append(x);ys.append(y)
    if not xs: return None
    return (min(xs)/SC,min(ys)/SC,(max(xs)+1)/SC,(max(ys)+1)/SC)
bad=0
def check(name, ok, msg):
    global bad
    if not ok:
        bad+=1
        print('  XX',name,msg)
def run(png):
    global bad
    js=json.load(open(png.replace('.png','.json')))
    im=Image.open(png).convert('RGB')
    panels=[e for e in js if e['t']=='panel']
    print(os.path.basename(png), len(js),'elements')
    for e in js:
        if e['t']=='button':
            r=e['rect']; face=(r[0]+2,r[1]+2,r[2]-4,r[3]-10)
            if e.get('dim'): continue
            cols=[hexc(e['color'])] if e['outline']=='fff1d6' else [hexc(e['color']),hexc(e['outline'])]
            bb=bbox(im,face,cols,tol=10)
            if bb is None: continue
            # исключаем иконку слева: берём только пиксели правее иконки (иконка до x+48) если она есть
            L=bb[0]-face[0];T=bb[1]-face[1];R=face[0]+face[2]-bb[2];B=face[1]+face[3]-bb[3]
            check(e['text'],T>=3 and B>=3 and abs(T-B)<=3,'button text %s face=%s margins T%.0f B%.0f'%(bb,face,T,B))
        elif e['t']=='label':
            r=e['rect']
            host=None
            cx,cy=r[0]+r[2]/2,r[1]+r[3]/2
            for p in panels:
                o=p['outer']
                if o[0]<=cx<=o[0]+o[2] and o[1]<=cy<=o[1]+o[3]:
                    if host is None or p['outer'][2]*p['outer'][3]<host['outer'][2]*host['outer'][3]: host=p
            if host is None: continue
            col=hexc(e['color'])
            bb=bbox(im,(r[0]-2,r[1]-2,r[2]+4,r[3]+4),[col],tol=14)
            if bb is None: continue
            i=host['inner']
            L=bb[0]-i[0];T=bb[1]-i[1];R=i[0]+i[2]-bb[2];B=i[1]+i[3]-bb[3]
            check(e['text'][:20],min(L,T,R,B)>=3,'label text %s inner=%s margins L%.0f T%.0f R%.0f B%.0f'%(bb,[round(v) for v in i],L,T,R,B))
    # wood pages: air around content
    for p in panels:
        o=p['outer']; i=p['inner']
        if o[2]<250: continue
        inside=[e for e in js if e['t'] in ('button','label') and i[0]<=e['rect'][0]+1 and e['rect'][0]+e['rect'][2]<=i[0]+i[2]+1 and i[1]<=e['rect'][1] and e['rect'][1]+e['rect'][3]<=i[1]+i[3]+30]
        btn=[e for e in inside if e['t']=='button']
        if not btn: continue
        left=min(b['rect'][0] for b in btn)-i[0]
        right=i[0]+i[2]-max(b['rect'][0]+b['rect'][2] for b in btn)
        bottom=i[1]+i[3]-max(b['rect'][1]+b['rect'][3] for b in btn)
        titles=[e for e in inside if e['t']=='label']
        top=None
        if titles:
            t=min(titles,key=lambda e:e['rect'][1])
            bb=bbox(im,(t['rect'][0],t['rect'][1],t['rect'][2],t['rect'][3]),[hexc(t['color'])],tol=14)
            if bb: top=bb[1]-i[1]
        print('   wood page free=%s air L%.0f R%.0f B%.0f T%s'%([round(v) for v in i],left,right,bottom,'%.0f'%top if top is not None else '?'))
for f in sys.argv[2:]:
    run(S+f)
print('violations:',bad)
