"""Original deterministic paper grain. No external assets or dependencies."""
from pathlib import Path
import struct,zlib,random
size=256
rng=random.Random(20261112)
rows=[]
for y in range(size):
 row=bytearray([0])
 for x in range(size):
  noise=rng.random()
  # Transparent, restrained fibers; the theme supplies the paper color.
  alpha=int(rng.random()*24) if noise<.76 else 0
  if (x*17+y*31)%257==0:alpha=37
  row.extend((64,59,42,alpha))
 rows.append(bytes(row))
def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows),9))+chunk(b'IEND',b'')
Path(__file__).resolve().parent.parent.joinpath('ReaderApp/Resources/PaperGrain.png').write_bytes(png)
