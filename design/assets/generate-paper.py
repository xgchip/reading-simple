"""Original seamless micro-fiber paper tiles. Python standard library only."""
from pathlib import Path
import random, math, struct, zlib
random.seed(20261112)
N=512
out=Path(__file__).parent
fibers=[[0.0]*N for _ in range(N)]
for _ in range(1700):
    x,y=random.randrange(N),random.randrange(N)
    length=random.randrange(2,13); angle=random.random()*math.tau
    value=random.choice([-.8,-.4,.4,.8])
    for step in range(length*3):
        xx=round(x+math.cos(angle)*step/3)%N; yy=round(y+math.sin(angle)*step/3)%N
        fibers[yy][xx]+=value*.18
# Independent stationary grain has no special edge; fibers wrap periodically.
grain=[[random.gauss(0,.68) for _ in range(N)] for _ in range(N)]
def chunk(kind,data):
    return struct.pack('!I',len(data))+kind+data+struct.pack('!I',zlib.crc32(kind+data)&0xffffffff)
for name,base,strength in [('paper-warm',(247,244,236),1.0),('paper-dark',(39,43,37),.55)]:
    rows=[]
    for y in range(N):
        row=bytearray([0])
        for x in range(N):
            v=(grain[y][x]+fibers[y][x]+.22*math.sin(x*math.tau/N)*math.cos(y*math.tau/N))*strength
            row.extend(max(0,min(255,round(c+v))) for c in base)
        rows.append(bytes(row))
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',N,N,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b'')
    (out/(name+'.png')).write_bytes(data)
print('Generated original 512px warm/dark PNG tiles')
