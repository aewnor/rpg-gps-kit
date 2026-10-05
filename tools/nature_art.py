"""Tiles transparentes de sotobosque y rocas; paleta compartida, IDs añadidos al final."""
from pixel import Sprite

def register(add):
    for name in ['lavender','flowers','grass','fern','reeds','mushrooms','pebbles','rock_0','rock_1','rock_2']:
        s=Sprite(16,16)
        if name.startswith('rock'):
            v=int(name[-1]);s.rect(3,10,11,4,'stone3');s.rect(2,8,11,4,'stone2');s.rect(4,5+v,7,5,'stone')
            s.hline(5,9,5+v,'white2');s.px(11,10,'stone3');s.px(5,12,'pine3')
        elif name=='pebbles':
            for x,y in [(3,10),(10,6),(8,12)]:s.rect(x,y,3,2,'stone2');s.hline(x,x+1,y,'stone')
        elif name=='mushrooms':
            for x,y in [(4,8),(10,11)]:s.rect(x,y,2,4,'white2');s.rect(x-2,y-1,5,2,'terra');s.px(x-1,y-1,'sand')
        else:
            for i,x in enumerate([3,7,11]):
                top=4+(i*3)%5;s.vline(x,top,13,'pine3');s.px(x-1,11,'pine2');s.px(x+1,9,'pine')
                if name=='lavender':s.vline(x,top,top+3,'blue');s.px(x+1,top+1,'white2')
                elif name=='flowers':s.rect(x-1,top,3,2,'white');s.px(x,top,'ochre')
                elif name=='reeds':s.vline(x,2,12,'pine2');s.rect(x-1,2,2,4,'ochre3')
                elif name=='fern':
                    for d in range(1,4):s.hline(x-d,x+d,top+d*2,'pine2')
                else:s.px(x-2,8,'pine2');s.px(x-1,10,'pine')
        add('nature_'+name,s,solid=name.startswith('rock'))
