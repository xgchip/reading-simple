from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent.parent
uid=lambda s:hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects=[]
def obj(key,value):objects.append(f'{uid(key)} = {{ {value} }};');return uid(key)
sources=sorted((root/'ReaderApp').glob('*.swift'))
resources=sorted(p for p in (root/'ReaderApp/Resources').glob('*') if p.name!='AppIcon.icns')+[root/'ReaderApp/Assets.xcassets']
srcids=[];resids=[];fileids=[]
for p in sources+resources:
 rel=str(p.relative_to(root));file=obj(rel,f'isa = PBXFileReference; lastKnownFileType = {"sourcecode.swift" if p.suffix==".swift" else "folder.assetcatalog" if p.suffix==".xcassets" else "text.xml" if p.suffix==".xcprivacy" else "text"}; path = "{rel}"; sourceTree = "<group>";');fileids.append(file)
 b=obj(rel+'build',f'isa = PBXBuildFile; fileRef = {file};');(srcids if p in sources else resids).append(b)
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MarginReader.app; sourceTree = BUILT_PRODUCTS_DIR;')
package=obj('package','isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/weichsel/ZIPFoundation.git"; requirement = { kind = exactVersion; version = 0.9.20; };')
pkgproduct=obj('pkgproduct',f'isa = XCSwiftPackageProductDependency; package = {package}; productName = ZIPFoundation;')
pkgbuild=obj('pkgbuild',f'isa = PBXBuildFile; productRef = {pkgproduct};')
src=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(srcids)},); runOnlyForDeploymentPostprocessing = 0;')
res=obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resids)},); runOnlyForDeploymentPostprocessing = 0;')
fw=obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({pkgbuild},); runOnlyForDeploymentPostprocessing = 0;')
group=obj('group',f'isa = PBXGroup; children = ({",".join(fileids)},{product},); sourceTree = "<group>";')
def configs(prefix,settings):
 ids=[]
 for mode in ['Debug','Release','AppStore']:
  extra='SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;' if mode=='Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
  if mode=='AppStore':extra+=' SWIFT_ACTIVE_COMPILATION_CONDITIONS = APPSTORE; ONLY_ACTIVE_ARCH = NO;'
  ids.append(obj(prefix+mode,f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings} {extra} }};'))
 return obj(prefix+'list',f'isa = XCConfigurationList; buildConfigurations = ({",".join(ids)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
projconfig=configs('proj','ARCHS = arm64; ONLY_ACTIVE_ARCH = YES; MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0;')
targetconfig=configs('target','PRODUCT_NAME = MarginReader; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; SKIP_INSTALL = NO; INSTALL_PATH = "$(LOCAL_APPS_DIR)"; DEAD_CODE_STRIPPING = YES; PRODUCT_BUNDLE_IDENTIFIER = com.haley.MarginReader; INFOPLIST_FILE = ReaderApp/Info.plist; CODE_SIGN_ENTITLEMENTS = ReaderApp/MarginReader.entitlements; ENABLE_APP_SANDBOX = YES; ENABLE_HARDENED_RUNTIME = YES; CODE_SIGN_STYLE = Automatic; COMBINE_HIDPI_IMAGES = YES; SWIFT_EMIT_LOC_STRINGS = YES; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0.0; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {targetconfig}; buildPhases = ({src},{fw},{res},); buildRules = (); dependencies = (); name = MarginReader; packageProductDependencies = ({pkgproduct},); productName = MarginReader; productReference = {product}; productType = "com.apple.product-type.application";')
project=obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {projconfig}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = (en,"zh-Hans",Base,); mainGroup = {group}; packageReferences = ({package},); projectDirPath = ""; projectRoot = ""; targets = ({target},);')
(root/'Reader.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n')
scheme=root/'Reader.xcodeproj/xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'MarginReader.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="MarginReader.app" BlueprintName="MarginReader" ReferencedContainer="container:Reader.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="MarginReader.app" BlueprintName="MarginReader" ReferencedContainer="container:Reader.xcodeproj"/></BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated Reader.xcodeproj')

# A dedicated scheme makes Organizer > Archive select the distribution-only configuration.
local_scheme=scheme/'MarginReader.xcscheme'
store_scheme=local_scheme.read_text().replace('buildConfiguration="Debug"','buildConfiguration="AppStore"').replace('buildConfiguration="Release"','buildConfiguration="AppStore"')
(scheme/'MarginReader-AppStore.xcscheme').write_text(store_scheme)
