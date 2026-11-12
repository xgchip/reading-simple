"""Copy approved original assets and emit CSS variables from UI-owned tokens."""
from pathlib import Path
import json,shutil
root=Path(__file__).resolve().parent.parent
src=root/'design';dest=root/'ReaderApp/Resources'
tokens=json.loads((src/'design-tokens.json').read_text())
shutil.copy2(src/'design-tokens.json',dest/'DesignTokens.json')
for name in ['paper-warm.png','paper-dark.png']:shutil.copy2(src/'assets'/name,dest/name)
shutil.copy2(src/'assets/LICENSE.md',dest/'PaperTexture-LICENSE.txt')
css=[]
for key,t in tokens['themes'].items():
 values={'desk':t['chrome'],'paper':t['canvas'],'ink':t['ink'],'muted':t['secondary'],'card':t['surface'],'line':t['line'],'accent':t['accent'],'highlight':t['highlight']+'66'}
 css.append(':root[data-theme="'+key+'"]{color-scheme:'+('dark' if key=='dark' else 'light')+';'+''.join('--'+k+':'+v+';' for k,v in values.items())+'}')
(dest/'ThemeVariables.css').write_text('\n'.join(css)+'\n')
print('Synced approved tokens and original paper tiles')
