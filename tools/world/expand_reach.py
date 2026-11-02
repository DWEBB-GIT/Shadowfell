"""Add the village, fishing and level 1–5 story route to an output copy.

python tools/world/expand_reach.py --source PROJECT --output STAGING
Preserves unrelated content. Review the result before copying individual files.
This recipe owns vr_* records; later hand edits should be made in Godot.
"""
import argparse
import base64
import copy
import json
import math
import random
import struct
import zlib
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
SRC, OUT = a.source.resolve(), a.output.resolve()
if SRC == OUT:
    p.error('Use a separate staging output directory.')
R = Path('data/terrain/new_map')
rng = random.Random(3110262)


def read(path):
    return json.loads((SRC/path).read_text(encoding='utf-8-sig'))


def write(path, data):
    target = OUT/path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')


def text(path, data):
    target = OUT/path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(data, encoding='utf-8')


def smooth(lo, hi, x):
    v = max(0, min(1, (x-lo)/(hi-lo)))
    return v*v*(3-2*v)


def distance(x, z, aa, bb):
    dx, dz = bb[0]-aa[0], bb[1]-aa[1]
    k = max(0, min(1, ((x-aa[0])*dx+(z-aa[1])*dz)/(dx*dx+dz*dz)))
    return math.hypot(x-aa[0]-k*dx, z-aa[1]-k*dz)


w, s = read(R/'spawns.json'), read(R/'scenery.json')
for d in [w,s]:
    for key, values in d.items():
        if isinstance(values,list):
            d[key] = [v for v in values if not isinstance(v,dict) or not v.get('id','').startswith('vr_')]

ROADS = [
 ('vr_inn_lane','Lantern Lane',2,[[-450,-193],[-465,-193],[-477,-193],[-477,-204],[-471,-204],[-466,-204]]),
 ('vr_willow_lane','Willow Lane',2.5,[[-450,-193],[-445,-180],[-426,-174],[-408,-174],[-396,-170]]),
 ('vr_mill_lane',"Miller's Lane",2.3,[[-477,-204],[-500,-215],[-522,-217]]),
 ('vr_hall_lane','Council Lane',2.5,[[-450,-193],[-454,-180],[-458,-174],[-458,-164],[-451,-164]]),
 ('vr_meadow_lane','Orchard Meadow',2.7,[[-350,-270],[-347,-289],[-331,-314],[-315,-329]]),
 ('vr_grave_road','The Mourning Road',2.7,[[-450,-425],[-416,-420],[-388,-432],[-365,-445],[-343,-456]]),
 ('vr_hamlet_lane','Hollow Lane',2.4,[[-388,-432],[-369,-407],[-342,-390],[-321,-382],[-309,-382]]),
 ('vr_crypt_lane','The Last Procession',2.4,[[-343,-456],[-329,-480],[-313,-486]]),
 ('vr_farm_yard','Holt Farmyard',2,[[-350,-270],[-345,-257],[-334,-252]]),
 ('vr_woodlot','The Woodlot',1.8,[[-380,-261],[-378,-274]]),
 ('vr_pig_track','Briarjaw Track',2,[[-331,-314],[-316,-298],[-303,-282]]),
]
AREAS = [(-450,-170,19),(-385,-173,23),(-535,-215,17),(-332,-309,28),
         (-343,-459,27),(-309,-384,23),(-313,-489,19),(-324,-251,10),(-378,-277,9),(-303,-282,14),(-369,-264,7)]
PONDS = [dict(id='vr_willow_pond',name='Willow Pond',position=[-383,-171],radius=9,fishTable='mere_fish',fishLevel=1,color='#59868d'),
         dict(id='vr_willow_cove',name='Willow Pond',position=[-377,-174],radius=5,fishTable='mere_fish',fishLevel=1,color='#59868d'),
         dict(id='vr_mill_pool',name="Miller's Pool",position=[-535,-215],radius=7,fishTable='mere_fish',fishLevel=1,color='#456873'),
         dict(id='vr_mill_cove',name="Miller's Pool",position=[-539,-218],radius=4,fishTable='mere_fish',fishLevel=1,color='#456873'),
         dict(id='vr_widow_pool',name="Widow's Mirror",position=[-289,-408],radius=6,fishTable='blackpool_fish',fishLevel=8,color='#343c58')]


def road_dist(x,z):
    return min(distance(x,z,aa,bb)-half for _,_,half,pts in ROADS for aa,bb in zip(pts,pts[1:]))


def opened(x,z):
    return min(road_dist(x,z)-3, *(math.hypot(x-cx,z-cz)-r for cx,cz,r in AREAS))


def haunt(x,z):
    return ((x+335)/76)**2+((z+445)/87)**2 < 1


# Add a real enterable inn, retaining the fitted interior and its door gap.
w['houses'] = [h for h in w.get('houses',[]) if h['id']!='tf_inn']
inn = copy.deepcopy(read(Path('data/world/world.json'))['buildings'][0])
inn.update(id='vr_lantern_inn',name='The Lantern Inn',position=[-465,-204])
w.setdefault('buildings',[]).append(inn)
hall = dict(id='vr_town_hall',name='Thornford Town Hall',position=[-450,-164],size=[10,8],
 shell='res://assets/scenery/TownHallShell.tscn',front='res://assets/scenery/TownHallFront.tscn',roof='res://assets/scenery/TownHallRoof.tscn',
 walls=[[-5,-4,5,-4],[5,-4,5,4],[-5,4,5,4],[-5,-4,-5,-1],[-5,1,-5,4]],
 furniture=[[2,1,.8]],light=[2,-2],rest=False)
w['buildings'].append(hall)
w.setdefault('houses',[]).extend([
 dict(id='vr_chapel',position=[-422,-230],size=[7,6],walls='stone',roof='slate',door='w',tower=True),
 dict(id='vr_apothecary',position=[-320,-390],size=[7,6],walls='timber',roof='slate',door='s',chimney=True),
 dict(id='vr_hollow_cottage',position=[-299,-395],size=[7,6],walls='plaster',roof='slate',door='w'),
 dict(id='vr_hollow_house',position=[-310,-368],size=[8,6],walls='timber',roof='thatch',door='s'),
 dict(id='vr_mausoleum',position=[-314,-499],size=[7,6],walls='stone',roof='slate',door='s')])
for building in w['buildings'] + [h for h in w['houses'] if h['id'].startswith('vr_')]:
    w.setdefault('pads',[]).append([*building['position'],max(building['size'])*.6])
for ident,name,half,pts in ROADS:
    w.setdefault('roads',[]).append(dict(id=ident,name=name,kind='lane',halfWidth=half,points=pts))
w.setdefault('water',[]).extend(PONDS)
for chest in w.get('chests',[]):
    if chest['id']=='tf_watch_chest':
        for item in chest.get('items',[]):
            if 'item' in item:item['id']=item.pop('item')
w['openingText']='Thornford. Mayor Alder needs help at Holt Orchard. The town hall stands at the south end of Council Lane.'
w['regions']=[dict(id='vr_hollow',name='Mourning Hollow',levels='4-5',rect=[-399,-525,143,182]),
              dict(id='vr_village',name='Thornford',levels='1-2',rect=[-489,-242,81,98])]+w['regions']
w['trainerOverrides'].update(brask='tf_rowan',nell='vr_rogue',odo='tf_scout',grue='vr_morrow',aveline='vr_lyra',tam='vr_tobin',briony='vr_morrow')
for n in w['npcSpawns']:
    if n['npc']=='tf_elsie':n['position']=[-461,-205]
    if n['npc']=='tf_iren':n['anvil']=[-435,-197]
w['npcSpawns'].extend([
 dict(npc='vr_mayor',position=[-448,-165],facing=270),
 dict(npc='vr_tobin',position=[-396,-170],facing=90),
 dict(npc='vr_rogue',position=[-462,-202],facing=180),
 dict(npc='vr_lyra',position=[-428,-230],facing=270),
 dict(npc='vr_morrow',position=[-317,-382],facing=180),
 dict(npc='vr_heda',position=[-342,-256],facing=210),
 dict(npc='vr_osric',position=[-378,-274],facing=180,workAt=[-378,-276])])
for e in w['enemySpawns']:
    if e['id']=='tf_revenant_1': e['position']=[-458,-332]
for kind,points in [
 ('vr_young_boar',[[-351,-287],[-337,-298],[-325,-310],[-344,-320],[-314,-331],[-324,-291]]),
 ('vr_watchman',[[-444,-239],[-479,-187]]),
 ('vr_gravewalker',[[-355,-461],[-331,-464],[-356,-478],[-331,-478]]),
 ('vr_hollow_archer',[[-369,-444],[-326,-441]]),
 ('vr_crypt_keeper',[[-312,-490]])]:
    for k,pos in enumerate(points): w['enemySpawns'].append(dict(id=f'{kind}_{k+1}',enemy=kind,position=pos))
for k,pos in enumerate([[-326,-252],[-320,-251],[-324,-247]]):
    w['enemySpawns'].append(dict(id=f'vr_farm_pig_{k+1}',enemy='vr_farm_pig',position=pos))
w['enemySpawns'].append(dict(id='vr_briarjaw_1',enemy='vr_briarjaw',position=[-303,-282]))
w.setdefault('placedLoot',[]).append(dict(id='vr_lost_pouch',model='coin_purse',scale=.7,position=[-524,-220],prompt="Recover Elsie's keepsake pouch",quest='vr_lost_brooch',reward=dict(item='vr_brooch_pouch')))

places=[('vr_willow','Willow Pond','place',[-395,-172],1,'Willows lean over clear water. Tobin keeps his tackle beside the landing.'),
 ('vr_mill',"Miller's Pool",'place',[-523,-217],1,'A quiet pool west of the inn. A good place to fish away an afternoon.'),
 ('vr_hall','Thornford Town Hall','town',[-453,-165],1,'Mayor Alder keeps the village rolls. Some names in the northern burial book have been scratched out.'),
 ('vr_meadow','Holt Meadow','hunt',[-332,-309],1,'Young boars root through broken orchard fencing. Beyond the meadow the woods grow darker.'),
 ('vr_graves','The Nameless Yard','ruin',[-343,-456],4,'Every headstone faces the old watch. Three family names have been chiselled away.'),
 ('vr_hollow','Mourning Hollow','village',[-310,-382],3,'Three shuttered homes shelter beneath the black trees. Morrow still tends the apothecary.'),
 ('vr_crypt','The Bell Crypt','dungeon',[-313,-486],5,'The procession ends at a sealed family crypt. Its keeper carries the missing names.'),
 ('vr_pool',"Widow's Mirror",'place',[-297,-404],4,'No birds drink here. Patient anglers sometimes see a second moon beneath the water.'),
 ('vr_boundary','The Orchard Boundary','story',[-369,-264],1,"The old stone points to a hedge north of the timber trail. Osric's new fence is three paces over the line. A faded village seal confirms Heda's claim."),
 ('vr_briar_den',"Briarjaw's Run",'hunt',[-303,-282],2,'Pig bristles cling to the briars. A lone wolf has been using this run to reach Holt Farm.')]
for ident,name,kind,pos,level,note in places:
    w.setdefault('pois',[]).append(dict(id=ident,name=name,kind=kind,at=pos,note=note,region='vr_hollow' if level>=3 else 'tf_reach',act='Chapter 1'))
    w.setdefault('subzones',[]).insert(0,dict(id=ident,name=name,at=pos,radius=18 if ident!='vr_graves' else 27))
for x,z,targets in [(-444,-189,['vr_hall','vr_willow','tf_cairn']),(-479,-193,['vr_mill','tf_town']),
                     (-357,-280,['vr_meadow','tf_town']),(-404,-422,['vr_graves','vr_hollow','tf_watch'])]:
    w['signposts'].append(dict(id=f'vr_sign_{x}_{z}',position=[x,z],points=[dict(to=t)for t in targets]))
w['stations']=[st for st in w['stations']if st['id']!='tf_hearth']
w['stations'].append(dict(id='vr_inn_hearth',name="Elsie's hearth",kind='fire',position=[-468.8,-207.4],radius=2.6))

# Clear only generated nature that blocks new paths, structures or pond bowls.
def must_clear(obj):
    if not obj.get('id','').startswith('tf_') or not obj['model'].startswith('res://glTF/'):return False
    x,z=obj['position']
    if math.hypot(x+343,z+469)<21 and any(v in obj['model']for v in ['Tree','Pine']):return True
    if road_dist(x,z)<2.5:return True
    if any(math.hypot(x-b['position'][0],z-b['position'][1])<max(b['size'])*.72+1 for b in w['buildings']+[h for h in w['houses']if h['id'].startswith('vr_')]):return True
    return any(math.hypot(x-pp['position'][0],z-pp['position'][1])<pp['radius']+2 for pp in PONDS)
s['props']=[v for v in s['props']if not must_clear(v)]
# The requested grass replacement preserves every original placement/rotation.
grass_count=0
for obj in s['props']:
    if '/Grass_' in obj['model']:
        obj['sourceModel']=obj['model'];obj['sourceScale']=obj.get('scale',1)
        obj['model']='res://assets/scenery/MeadowGrass.tscn'
        obj['scale']=round(max(.6,min(1.15,obj.get('scale',1)*2)),2)
        grass_count+=1


def prop(model,x,z,scale=1,rotation=0,collider=None,**extra):
    d=dict(id=f'vr_prop_{len(s["props"])}',model=model,position=[round(x,2),round(z,2)],scale=scale,rotation=rotation,**extra)
    if collider:d['collider']=collider
    s['props'].append(d)


# Workplaces, pond landings and modest street furniture.
prop('res://assets/scenery/PondDock.tscn',-393,-171,1,0)
prop('res://assets/scenery/PondDock.tscn',-525,-216,.8,180)
prop('res://assets/scenery/ChoppingBlock.tscn',-378,-276,1,0,.4)
prop('waymarker',-369,-264,1,0,.3)
prop('thorn_boar',-319,-263,.7,0,rotation3=[0,90,90],tint='#9a8c7b')
for x in [-329,-325,-321]:
    for z in [-243,-258]:prop('fence',x,z,1,0,.3)
for z in [-246,-250,-254]:prop('fence',-317,z,1,90,.3)
for model,x,z,scale,r in [('fishing_rod',-396,-168,1,20),('crate',-398,-173,.7,0),('awning',-398,-167,.8,90),
 ('well',-308,-387,1,0),('forge',-432,-198,.65,0),('standing_stone',-429,-231,1,0),
 ('standing_stone',-349,-445,1.4,0),('standing_stone',-337,-445,1.4,0),('crate',-317,-379,.8,25)]:
    prop(model,x,z,scale,r,.3 if model not in ['fishing_rod','awning'] else None)
for x in [-359,-351,-335,-327]:
    for z in [-466,-478]:
        prop('grave0' if x%3 else 'grave1',x,z,1.2,rng.uniform(-12,12),.45)
        if x in [-359,-327]: prop('res://assets/environment/nature/trees/DeadTree_2.gltf',x-2,z-3,1.1,35,.3)
for x,z in [(-364,-485),(-352,-485),(-340,-485),(-328,-485),(-319,-476)]:
    prop('fence',x,z,1.2,0,.4)
for x,z in [(-458,-177),(-425,-184),(-507,-215),(-397,-174),(-391,-429),(-343,-447),(-317,-382)]:
    s.setdefault('lights',[]).append(dict(id=f'vr_lamp_{x}_{z}',position=[x,z],height=1.5,intensity=3.2,distance=9,
       color='#84b9bf' if haunt(x,z) else '#ffd29b',brazier=True,flicker=True))
for pond in PONDS:
    cx,cz=pond['position'];rad=pond['radius']
    for k in range(9):
        angle=k*math.tau/9+.2
        x,z=cx+math.cos(angle)*(rad+1.3),cz+math.sin(angle)*(rad+1.3)
        if road_dist(x,z)<1.5:continue
        prop('res://assets/environment/nature/rocks/Rock_Medium_2.gltf',x,z,.25+rng.random()*.25,rng.random()*360)
        prop('res://assets/environment/nature/plants/Fern_1.gltf',x+.6,z+.5,.25+rng.random()*.15,rng.random()*360)
    for dx,dz in [(-rad-3,-2),(rad+2,3)]:
        if road_dist(cx+dx,cz+dz)>1.5 and not any(math.hypot(cx+dx-v['position'][0],cz+dz-v['position'][1])<v['radius']+1 for v in PONDS):
            prop('res://assets/environment/nature/trees/CommonTree_2.gltf',cx+dx,cz+dz,1.2,rng.random()*360,.3,tint='#a6b499')
for x,z in [(-385,-168),(-381,-176),(-377,-174),(-536,-212),(-532,-216)]:
    prop('res://assets/scenery/WaterLilies.tscn',x,z,1,rng.random()*360,heightOffset=1.12)
for ident,_,_,pos,_,_ in places:
    if 'graves' in ident or 'hollow' in ident:
        s.setdefault('motes',[]).append(dict(id=ident+'_motes',position=pos,radius=8,count=14,color='#9ac0c8'))

# Author the new connected clearings and haunted biome into the sculpt layer.
data=(SRC/R/'world.bin').read_bytes();x0,z0,cell=struct.unpack_from('<fff',data,8)
tile,tx,tz=struct.unpack_from('<III',data,24);tiles={};edited=set();layer=read(R/'sculpt.json');layers={}


def unpack(i,j):
    if (i,j) in tiles:return tiles[i,j]
    off,size=struct.unpack_from('<II',data,36+(j*tx+i)*8)
    raw=zlib.decompress(data[off:off+size]) if size else bytes(4356)
    dd=struct.unpack_from('<1089h',raw);columns=[0]*33;heights=[]
    for zz in range(33):
        run=0
        for xx in range(33):
            columns[xx]+=dd[zz*33+xx];run+=columns[xx];heights.append(run*.05-50 if size else -12)
    tiles[i,j]=[heights,list(raw[2178:3267]),list(raw[3267:4356])]
    return tiles[i,j]


for b in range(math.ceil((-530-z0)/cell),math.floor((-140-z0)/cell)+1):
    for aa in range(math.ceil((-565-x0)/cell),math.floor((-260-x0)/cell)+1):
        x,z=x0+aa*cell,z0+b*cell;od=opened(x,z)
        shade=haunt(x,z)
        if od>12 and not shade:continue
        t=unpack(aa//32,b//32);idx=(b%32)*33+aa%32
        oldh,oldw,info=t[0][idx],t[1][idx],t[2][idx]
        blend=1-smooth(0,12,od)
        level=3.2+max(0,-z-260)*.012
        # Gentle terrain follows the original district's elevation ramp.
        desired=level+max(0,od)*.22
        nh=round((oldh+(desired-oldh)*blend)*20)/20
        nw=round(oldw+(255-oldw)*blend)
        surf=15 if shade else (1 if od<9 else info&15)
        if not shade and any(pp['radius']+.4<math.hypot(x-pp['position'][0],z-pp['position'][1])<pp['radius']+2.3 for pp in PONDS):surf=7
        if blend<.5 and not shade:surf=info&15
        key=f'{aa//32},{b//32}'
        if key not in layers:
            prev=layer['tiles'].get(key,{})
            layers[key]=[list(struct.unpack('<1024h',zlib.decompress(base64.b64decode(prev[k])))) if k in prev else [0 if k=='h' else -1]*1024 for k in 'hws']
        li=(b%32)*32+aa%32
        layers[key][0][li]+=round((nh-oldh)*20);layers[key][1][li]=nw;layers[key][2][li]=surf
        ii=[aa//32-1,aa//32]if aa%32==0 else[aa//32]
        jj=[b//32-1,b//32]if b%32==0 else[b//32]
        for i in ii:
            for j in jj:
                if 0<=i<tx and 0<=j<tz:
                    tt=unpack(i,j);q=(b-j*32)*33+aa-i*32
                    tt[0][q],tt[1][q],tt[2][q]=nh,nw,(info&240)|surf;edited.add((i,j))
for key,vs in layers.items():layer['tiles'][key]={k:base64.b64encode(zlib.compress(struct.pack('<1024h',*v))).decode()for k,v in zip('hws',vs)}
write(R/'sculpt.json',layer)
index=bytearray(tx*tz*8);blobs=[];offset=36+len(index)
for j in range(tz):
    for i in range(tx):
        k=j*tx+i
        if (i,j) in edited:
            hh,ww,ff=tiles[i,j];q=[round((v+50)*20)for v in hh];delta=[]
            for zz in range(33):
                for xx in range(33):
                    dx=q[zz*33+xx]-(q[zz*33+xx-1]if xx else 0)
                    up=q[(zz-1)*33+xx]-(q[(zz-1)*33+xx-1]if xx else 0)if zz else 0
                    delta.append(dx-up)
            blob=zlib.compress(struct.pack('<1089h',*delta)+bytes(ww)+bytes(ff))
        else:
            off,size=struct.unpack_from('<II',data,36+k*8);blob=data[off:off+size]
        struct.pack_into('<II',index,k*8,offset if blob else 0,len(blob));blobs.append(blob);offset+=len(blob)
(OUT/R/'world.bin').write_bytes(data[:36]+index+b''.join(blobs))

# Thick dead woodland frames the haunted lanes, but never spawns on them.
protected=[v['position']for key in ['npcSpawns','enemySpawns','signposts']for v in w[key]]
for gz in range(-518,-346,7):
    for gx in range(-394,-269,7):
        x,z=gx+rng.uniform(-2,2),gz+rng.uniform(-2,2)
        if not haunt(x,z)or opened(x,z)<2 or road_dist(x,z)<4:continue
        if any(math.hypot(x-v[0],z-v[1])<4 for v in protected):continue
        if any(math.hypot(x-v['position'][0],z-v['position'][1])<max(v['size'])*.75+2 for v in w['houses']):continue
        if any(math.hypot(x-v['position'][0],z-v['position'][1])<v['radius']+2 for v in PONDS):continue
        prop('res://glTF/'+rng.choice(['DeadTree_1','DeadTree_2','TwistedTree_1','Pine_1'])+'.gltf',x,z,round(rng.uniform(.95,1.45),2),rng.random()*360,.3,tint='#86959a')
write(R/'spawns.json',w);write(R/'scenery.json',s)

# Content stays in canonical Game Data files.
def merge(file,key,rows):
    d=read(Path('data/'+file+'.json'));d[key]=[v for v in d[key]if not v['id'].startswith('vr_')]+rows
    return d


npcs=[dict(id='vr_mayor',name='Mayor Alder',title='Mayor of Thornford',level=10,model='tam',rig='warden',tint='#a1a6b7',dialogue='vr_mayor',reeve=True),
 dict(id='vr_tobin',name='Tobin Reed',title='Angler and Fishing Trainer',mapIcon='fishing',level=8,model='tam',rig='warden',shop='vr_tackle',dialogue='vr_tobin',tool='fishing_rod',toolScale=.8,idlePose='fish'),
 dict(id='vr_rogue',name='Mira Vale',title='Rogue Trainer',mapIcon='trainer',level=10,model='mara',rig='warden',tint='#9c9ab6',dialogue='vr_rogue'),
 dict(id='vr_lyra',name='Sister Lyra',title='Paladin Trainer',mapIcon='trainer',level=10,model='warden',rig='warden',tint='#c4c1a6',dialogue='vr_lyra'),
 dict(id='vr_morrow',name='Morrow Finch',title='Apothecary and Occultist Trainer',mapIcon='trainer',level=10,model='innkeeper',rig='warden',tint='#98a59a',shop='vr_apothecary',dialogue='vr_morrow'),
 dict(id='vr_heda',name='Heda Holt',title='Orchard Farmer',level=6,model='innkeeper',rig='warden',tint='#bda978',dialogue='vr_heda'),
 dict(id='vr_osric',name='Osric Moss',title='Woodcutter',level=6,model='mara',rig='warden',tint='#a0ad8b',dialogue='vr_osric',tool='res://assets/scenery/WoodAxe.tscn',toolScale=1)]
nd=merge('npcs','npcs',npcs)
for n in nd['npcs']:
    if n['id']=='tf_rowan':n['title']='Watch Captain and Warden Trainer'
    if n['id']=='tf_scout':n['title']='Scout and Ranger Trainer'
write(Path('data/npcs/npcs.json'),nd)
enemies=[dict(id='vr_young_boar',base='wild_boar',name='Young Bristle Boar',model='thorn_boar',level=1,scale=1,tint='#ffffff',detection=5,roam=2.5,respawn=60),
 dict(id='vr_watchman',base='town_guard',name='Thornford Watchman',level=12,roam=1.5),
 dict(id='vr_gravewalker',base='ghoul',name='Nameless Gravewalker',level=4,detection=7,respawn=100),
 dict(id='vr_hollow_archer',base='archer',name='Hollow Watch Archer',level=4,detection=9,respawn=120),
 dict(id='vr_crypt_keeper',base='brute',name='Keeper of the Lost Names',level=5,detection=8,respawn=300),
 dict(id='vr_farm_pig',base='wild_boar',name="Heda's Pig",model='thorn_boar',level=1,scale=.8,tint='#c9b8aa',lawful='livestock',xp=0,roam=1,respawn=120),
 dict(id='vr_briarjaw',base='ridge_wolf',name='Briarjaw',level=2,scale=1.05,pack=0,detection=7,roam=1.5,respawn=120)]
ed=merge('enemies','enemies',enemies)
for e in ed['enemies']:
    if e['id']=='tf_revenant':e['level']=2
write(Path('data/npcs/enemies.json'),ed)


def quest(i,name,giver,summary,offer,objs,reward,requires=None,**extra):
    return dict(id=i,name=name,map='new',giver=giver,turnIn=giver,summary=summary,offer=offer,
      progress=extra.pop('progress','Follow the signposted road. Return here when your work is done.'),
      complete=extra.pop('complete','Thank you. Take this for your trouble, and keep your lantern lit.'),
      objectives=objs,reward=reward,requires=requires or [],**extra)


def ex(i,target,label):return dict(id=i,type='examine',target='poi:'+target,label=label,location=target)
def kill(i,target,count,label,loc):return dict(id=i,type='kill',target=target,count=count,label=label,location=loc)


quests=[quest('vr_first_hunt','Roots Beneath the Orchard','vr_mayor',
 'Thin three young boars at Holt Meadow east of Thornford, then report to Mayor Alder at the town hall.',
 "The orchard fence is down again. Three fewer boars would give Holt time to mend it. Look over the meadow while you are there. The watch used to bring timber down that lane, before their lanterns went out.",
 [kill('boars','vr_young_boar',3,'Young bristle boars defeated','vr_meadow'),ex('meadow','vr_meadow','Look over Holt Meadow')],
 dict(coins=25,xp=260),autoAccept=True,level=[1,2],complete="Holt can mend a fence. What troubles me is why the watch stopped bringing timber. Captain Rowan has a job for you on the lantern road."),
 quest('vr_names','The Names They Left Behind','vr_mayor',
 'Follow the Mourning Road beyond the watch. Examine the Nameless Yard and defeat three gravewalkers, then return to Mayor Alder.',
 "Rowan says the Bellkeeper is gone. Yet the burial rolls still change by themselves. Three names vanished last night. Follow the road east of the watch to our family graves. Read the stones, and lay three of their restless dead to rest.",
 [ex('stones','vr_graves','Read the nameless headstones'),kill('dead','vr_gravewalker',3,'Gravewalkers laid to rest','vr_graves')],
 dict(coins=35,xp=650,items=[dict(item='healing_draught',count=2)]),['tf_bell'],level=[4,5],complete="Alder reads the marks you copied. 'My mother's family. And Elsie's. Someone has been taking more than bodies. The last procession went down to the old crypt.'"),
 quest('vr_crypt','What the Bell Remembers','vr_mayor',
 'Find the Bell Crypt beyond the graveyard and defeat the Keeper of the Lost Names. Return to Mayor Alder.',
 "The crypt keeper held the family seals. If the dead are being stripped of their names, he will know why. Follow the last procession beyond the graves. Bring his watch to an end.",
 [ex('crypt','vr_crypt','Find the Bell Crypt'),kill('keeper','vr_crypt_keeper',1,'Keeper of the Lost Names defeated','vr_crypt')],
 dict(coins=55,xp=650,items=[dict(item='strong_healing_draught',count=2)]),['vr_names'],level=5,setsFlag='vr_names_restored',complete="Alder presses the old seals into the burial book. Names return beneath his fingers. 'We will remember them properly now. As for the hand that woke the keeper... that road leads farther than Thornford.'"),
 quest('vr_perch','Supper at the Lantern','tf_elsie',
 'Catch three Gloomwater perch at Willow Pond or Miller\'s Pool and bring them to Elsie inside the Lantern Inn.',
 "Tobin teaches Fishing by Willow Pond. If you have a rod, three perch would make a fine supper. You can fish the mill pool too. Take your time. Some work is better done sitting quietly.",
 [dict(id='perch',type='collect',target='gloomwater_perch',count=3,label='Fresh perch for Elsie',location='vr_willow')],
 dict(coins=16,xp=120),level=[1,3]),
 quest('vr_hollow_story','The House That Kept a Light','vr_morrow',
 'Visit Widow\'s Mirror beside Mourning Hollow, then return to Morrow at the apothecary. This local tale is independent of the watch story.',
 "The widow kept a light beside that pool after her son failed to return. Folk call it haunted. I call it a place to remember someone. Go and look, if you can spare a moment from hunting monsters.",
 [ex('mirror','vr_pool',"Visit Widow's Mirror")],dict(coins=12,xp=140),level=[3,5],complete="Morrow sets a cup beside the window. 'She knew he was gone. The light was for anyone else who might still find their way home.'"),
 quest('vr_fence_dispute','Three Paces Over the Line','vr_mayor',
 "Heda and Osric disagree over the orchard boundary. Read the old boundary stone beside their plots and report to Mayor Alder.",
 "Heda says Osric moved the fence. Osric says the hedge was never straight. Neither will speak to the other. Look at the old boundary stone by the orchard trail and bring me what it actually says.",
 [ex('boundary','vr_boundary','Read the old boundary stone')],dict(coins=10,xp=100),level=[1,3],setsFlag='vr_boundary_settled',
 complete="Three paces. Alder sighs. 'Then the fence goes back three paces, and Osric uses the timber trail. No fines, no feuds. I will see that they both hear it.'"),
 quest('vr_pig_wolf','One Pig Too Many','vr_heda',
 "Briarjaw has killed two of Heda's pigs. Track the lone wolf east of Holt Meadow and return to Heda.",
 "First the orchard fence, now my pigs. Two gone, and that grey wolf is bold enough to come back for a third. They call it Briarjaw. Follow its run east of the meadow and put a stop to it.",
 [kill('wolf','vr_briarjaw',1,'Briarjaw defeated','vr_briar_den')],dict(coins=16,xp=150),level=2,setsFlag='vr_pigs_safe',
 complete="Heda checks the pen before she takes your hand. 'Still three. You have no idea how glad I am to count the same number twice. Here, for your trouble.'"),
 quest('vr_reed_message','A Word Across the Water','vr_heda',
 "Carry Heda's request for fence reeds to Tobin at Willow Pond.",
 "If you are going past Willow Pond, tell Tobin I will trade orchard apples for a bundle of his cut reeds. The pig shelter needs a new roof, and neither of us has time to leave our work.",
 [dict(id='message',type='talk',target='vr_tobin',label="Deliver Heda's request to Tobin")],dict(coins=8,xp=70),level=[1,3],
 complete="Apples for reeds? Done. Tobin wipes his hands. 'I will take a bundle round after dusk. Thanks for carrying the word.'"),
 quest('vr_lost_brooch','Lost in the Rushes','tf_elsie',
 "Find Elsie's keepsake pouch beside Miller's Pool and return it to her inside the Lantern Inn.",
 "I took a walk by the mill pool before opening the inn. Somewhere near the rushes I dropped a little pouch with Mother's brass brooch inside. It is worth almost nothing to anyone else. Would you look for it?",
 [dict(id='pouch',type='collect',target='vr_brooch_pouch',count=1,label="Elsie's keepsake pouch",location='vr_mill')],
 dict(coins=12,xp=90),level=[1,3],complete="Elsie opens the pouch, then closes her fingers round the brooch. 'I thought I had lost her twice. Thank you. Have something for the road.'")]
for q in quests:
    if q['id']=='vr_reed_message':q['turnIn']='vr_tobin'
qd=merge('quests','quests',quests)
for q in qd['quests']:
    if q['id']=='tf_lanterns':
        q.update(autoAccept=False,requires=['vr_first_hunt'],level=[2,3]);q['reward']['xp']=400
        q['complete']="Rowan turns the broken lantern in his hands. 'The Bellkeeper's mark. Follow the road north to the old watch. Fen can show you the western loop if you want to clear Wolf Hollow first.'"
    if q['id']=='tf_briar':q.update(requires=['vr_first_hunt'],level=[2,3]);q['summary']+=' This woodland errand is optional.'
    if q['id']=='tf_bell':
        q.update(requires=['tf_lanterns'],level=[3,4]);q['reward']['xp']=550
        q['offer']="The watch's broken lantern bears the Bellkeeper's mark. Follow the north road to the ruined tower. End his silent watch, then climb to Dawnstone Shrine and tell me what you find."
write(Path('data/quests/quests.json'),qd)
greetings={
 'vr_mayor':"Thornford survives because people help their neighbours. Start with the orchard. The missing watch can wait until you know the roads.",
 'vr_tobin':"Still water, a sound rod, and a little patience. I teach Fishing here and sell the tackle. The Lantern Inn buys perch for supper.",
 'vr_rogue':"A crowded taproom teaches you where people look, and where they don't. If you need rogue training, take the quiet chair.",
 'vr_lyra':"A light is most useful where the road grows dark. I teach paladins here, beside the chapel.",
 'vr_morrow':"The others shutter their windows before dusk. I keep the apothecary open. Herbs and occultist training, if you have come prepared.",
 'vr_heda':"Boars under the apple trees, a wolf at the pigpen, and Osric shifting my fence. The orchard does not stop growing just because people are arguing.",
 'vr_osric':"I cut timber for the village. I do not steal orchards. Heda can measure her hedge again if she likes. Until then, there is wood to split.",
 'tf_scout':"The wolf hollow is south of this camp. Rangers train here, where we can see the tracks. This woodland job is yours to take when you are ready.",
 'tf_rowan':"Mayor Alder keeps the village steady. I keep its watch. Wardens train beside this watch house; the northern road is our business.",
 'tf_elsie':"Come in and shut out the road. A bed is two silver. You can make this inn your home, or help me put supper on the table."}
dd=merge('dialogue','dialogues',[dict(id=i,greetings=[dict(text=t)],topics=[],nodes=[])for i,t in greetings.items()if i.startswith('vr_')])
for d in dd['dialogues']:
    if d['id']in greetings:d['greetings']=[dict(text=greetings[d['id']])]
    if d['id']=='vr_heda':d['greetings'].append(dict(text="Still three pigs this morning. The orchard is quieter with Briarjaw gone. Now if only the fence would mend itself.",when=dict(flag='vr_pigs_safe')))
    if d['id']=='vr_osric':d['greetings'].append(dict(text="Three paces. I moved it back. Heda has her hedge, I have the timber trail, and perhaps we can all get on with our work.",when=dict(flag='vr_boundary_settled')))
write(Path('data/quests/dialogue.json'),dd)
wd=read(Path('data/world/world.json'))
wd['locations']=[v for v in wd['locations']if not v['id'].startswith('vr_')]+[dict(id=i,name=n,position=pos,radius=18)for i,n,_,pos,_,_ in places]
write(Path('data/world/world.json'),wd)
td=read(Path('data/ui/text.json'))
for i,_,_,_,_,note in places:td['examine']['poi:'+i]=note
write(Path('data/ui/text.json'),td)
sd=read(Path('data/npcs/shops.json'));newshops=[]
for source,ident,name in [('tam_outfitters','vr_tackle',"Tobin's Tackle"),('briony_herbs','vr_apothecary',"Morrow's Apothecary")]:
    shop=copy.deepcopy(next(v for v in sd['shops']if v['id']==source));shop.update(id=ident,name=name);newshops.append(shop)
sd['shops']=[v for v in sd['shops']if not v['id'].startswith('vr_')]+newshops
write(Path('data/npcs/shops.json'),sd)
it=read(Path('data/items/items.json'))
it['items']=[v for v in it['items']if v['id']!='vr_brooch_pouch']+[
 dict(id='vr_brooch_pouch',name="Elsie's keepsake pouch",kind='document',rarity='quest',quest=True,stack=1,price=0,model='coin_purse',icon='coin_purse',description='A small pouch holding a worn brass brooch. Elsie Reed lost it beside the mill pool.')]
write(Path('data/items/items.json'),it)
law=read(Path('data/npcs/infamy.json'))
law['jurisdictions']=[v for v in law['jurisdictions']if v['id']!='vr_thornford']+[
 dict(id='vr_thornford',name='Thornford',reeve='vr_mayor',regions=['vr_village','tf_reach'],gaol=[-457,-174],gaolName='the Thornford watch yard')]
write(Path('data/npcs/infamy.json'),law)

# Editable native scenes: original geometry, no dependency on paid generation.
class Scene:
    def __init__(self,name):self.name=name;self.resources=[];self.nodes=[f'[node name="{name}" type="Node3D"]'];self.count=0
    def res(self,kind,fields):
        self.count+=1;i=str(self.count);self.resources.append(f'[sub_resource type="{kind}" id="{i}"]\n'+fields);return i
    def mat(self,c):return self.res('StandardMaterial3D',f'albedo_color = Color({c[0]}, {c[1]}, {c[2]}, 1)\nroughness = 0.9')
    def node(self,name,mesh,mat,pos,scale=(1,1,1),rotation=(0,0,0),parent='.'):
        self.nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]\nposition = Vector3{tuple(pos)}\nrotation_degrees = Vector3{tuple(rotation)}\nscale = Vector3{tuple(scale)}\nmesh = SubResource("{mesh}")\nmaterial_override = SubResource("{mat}")')
    def box(self,name,mat,pos,size,parent='.'):
        mesh=self.res('BoxMesh',f'size = Vector3{tuple(size)}');self.node(name,mesh,mat,pos,parent=parent)
    def sphere(self,name,mat,pos,r,scale=(1,1,1),parent='.'):
        mesh=self.res('SphereMesh',f'radius = {r}\nheight = {r*2}\nradial_segments = 10\nrings = 5');self.node(name,mesh,mat,pos,scale,parent=parent)
    def save(self,path):text(Path(path),f'[gd_scene load_steps={self.count+1} format=3]\n\n'+'\n\n'.join(self.resources+self.nodes)+'\n')


boar=Scene('ThornBoar');brown=boar.mat((.29,.18,.11));muzzle=boar.mat((.39,.25,.18));ivory=boar.mat((.87,.81,.64));black=boar.mat((.08,.06,.04))
boar.nodes.append('[node name="Torso" type="Node3D" parent="."]\nposition = Vector3(0, 0.64, 0)')
boar.sphere('Body',brown,[0,0,0],.48,[.9,.85,1.45],'Torso')
boar.nodes.append('[node name="Head" type="Node3D" parent="Torso"]\nposition = Vector3(0, -0.03, 0.65)')
boar.sphere('HeadShape',muzzle,[0,0,0],.31,[.9,1,1.2],'Torso/Head')
boar.sphere('Snout',muzzle,[0,-.10,.32],.21,[1,.8,.8],'Torso/Head')
for side in [-1,1]:
    boar.sphere('Eye'+str(side),black,[side*.24,.10,.11],.035,parent='Torso/Head')
    cone=boar.res('CylinderMesh','top_radius = 0.012\nbottom_radius = 0.06\nheight = 0.24\nradial_segments = 6')
    boar.node('Tusk'+str(side),cone,ivory,[side*.19,-.035,.35],rotation=(-25,0,side*-18),parent='Torso/Head')
    ear=boar.res('CylinderMesh','top_radius = 0.0\nbottom_radius = 0.13\nheight = 0.28\nradial_segments = 3')
    boar.node('Ear'+str(side),ear,brown,[side*.23,.30,-.03],rotation=(15,0,side*-25),parent='Torso/Head')
for name,x,z in [('Leg_L',-.29,.45),('Leg_R',.29,.45),('Arm_L',-.29,-.43),('Arm_R',.29,-.43)]:
    boar.nodes.append(f'[node name="{name}" type="Node3D" parent="."]\nposition = Vector3({x}, 0.36, {z})')
    boar.box(name+'Shin',brown,[0,-.17,0],[.16,.34,.18],name)
    boar.box(name+'Hoof',black,[0,-.31,.025],[.18,.10,.23],name)
for k in range(5):
    bristle=boar.res('CylinderMesh','top_radius = 0.0\nbottom_radius = 0.075\nheight = 0.16\nradial_segments = 3')
    boar.node('Bristle'+str(k),bristle,black,[0,.43,-.45+k*.19],parent='Torso')
boar.save('assets/models/characters/thorn_boar.tscn')
for part in ['Shell','Front','Roof']:
    sc=Scene('TownHall'+part);plaster=sc.mat((.58,.52,.41));wood=sc.mat((.25,.17,.12));stone=sc.mat((.40,.42,.41));roof=sc.mat((.23,.30,.35));gold=sc.mat((.66,.51,.25))
    if part=='Shell':
        for name,pos,size,mat in [('Floor',[0,0,0],[10,.15,8],wood),('Back',[0,1.6,-4],[10,3.2,.25],plaster),('East',[5,1.6,0],[.25,3.2,8],plaster),('WestA',[-5,1.6,-2.5],[.25,3.2,3],plaster),('WestB',[-5,1.6,2.5],[.25,3.2,3],plaster),('Desk',[2,.65,1],[2,1.3,.9],wood),('ClerkChair',[2,.5,-.4],[.8,1,.8],wood),('Records',[-1,1,-3.6],[3,2,.6],wood),('CouncilBanner',[1,2.1,-3.8],[1,1.4,.12],gold)]:sc.box(name,mat,pos,size)
    elif part=='Front':sc.box('FrontWall',plaster,[0,1.6,4],[10,3.2,.25])
    else:
        for side in [-1,1]:
            mm=sc.res('BoxMesh','size = Vector3(11, 0.25, 5.5)');sc.node('Roof'+str(side),mm,roof,[0,4.3,side*2.1],rotation=(side*32,0,0))
        sc.box('Ridge',wood,[0,5.5,0],[11,.2,.3])
    sc.save('assets/scenery/TownHall'+part+'.tscn')
sc=Scene('PondDock');wood=sc.mat((.36,.25,.15));dark=sc.mat((.22,.16,.1))
for k in range(8):sc.box('Plank'+str(k),wood,[-1.5+k*.43,.12,0],[.39,.16,1.8])
for x in [-1.4,1.4]:
    for z in [-.75,.75]:sc.box(f'Post{x}{z}',dark,[x,-.15,z],[.16,.8,.16])
sc.save('assets/scenery/PondDock.tscn')
sc=Scene('WaterLilies');leaf=sc.mat((.26,.43,.22));petal=sc.mat((.77,.56,.64))
for k,(x,z,r) in enumerate([(-.25,0,.24),(.16,.18,.3),(.2,-.25,.22)]):
    disk=sc.res('CylinderMesh',f'top_radius = {r}\nbottom_radius = {r}\nheight = 0.018\nradial_segments = 10')
    sc.node('Leaf'+str(k),disk,leaf,[x,0,z])
sc.sphere('Bloom',petal,[.16,.06,.18],.075,[1,.5,1])
sc.save('assets/scenery/WaterLilies.tscn')
sc=Scene('WoodAxe');wood=sc.mat((.35,.23,.13));iron=sc.mat((.5,.53,.54))
sc.box('Handle',wood,[0,-.12,0],[.055,.62,.055]);sc.box('Blade',iron,[.11,.11,0],[.28,.18,.07]);sc.save('assets/scenery/WoodAxe.tscn')
sc=Scene('ChoppingBlock');wood=sc.mat((.39,.28,.16));bark=sc.mat((.23,.18,.12))
log=sc.res('CylinderMesh','top_radius = 0.45\nbottom_radius = 0.5\nheight = 0.5\nradial_segments = 10')
sc.node('Log',log,bark,[0,.25,0]);top=sc.res('CylinderMesh','top_radius = 0.44\nbottom_radius = 0.44\nheight = 0.02\nradial_segments = 10')
sc.node('CutFace',top,wood,[0,.51,0]);sc.save('assets/scenery/ChoppingBlock.tscn')
write(Path('docs/reach-expansion-manifest.json'),dict(continentMetres=[2048,3072],visualAssets='Original Godot-native geometry, authored for Shadowfell; no external textures.',
  grassReplacements=grass_count,terrainTiles=[list(v)for v in sorted(edited)],mainQuests=['vr_first_hunt','tf_lanterns','tf_bell','vr_names','vr_crypt'],
  optionalQuests=['tf_briar','tf_herbs','vr_perch','vr_hollow_story','vr_fence_dispute','vr_pig_wolf','vr_reed_message','vr_lost_brooch'],places=places))
print(f'Expanded Reach: {grass_count} placed grasses replaced; {len(edited)} terrain tiles; {len(s["props"])} props; fishing ponds, real interiors, level 1–5 route.')
