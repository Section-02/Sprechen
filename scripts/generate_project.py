#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Run after adding Swift files."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent

def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()

def quoted(value):
    return '"' + value.replace('"', '\\"') + '"'

objects = []
def obj(key, value):
    objects.append(f'{uid(key)} = {{ {value} }};')
files = sorted([*root.glob('Sources/SprechenCore/*.swift'), *root.glob('App/*.swift')])
refs, builds = [], []
for file in files:
    path = str(file.relative_to(root)); ref = uid('ref:'+path); build = uid('build:'+path)
    obj('ref:'+path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = SOURCE_ROOT;')
    obj('build:'+path, f'isa = PBXBuildFile; fileRef = {ref};')
    refs.append(ref); builds.append(build)
resources = []
for path in ['App/PrivacyInfo.xcprivacy', 'App/Assets.xcassets']:
    obj('ref:'+path, f'isa = PBXFileReference; lastKnownFileType = {"folder.assetcatalog" if path.endswith("xcassets") else "text.xml"}; path = {quoted(path)}; sourceTree = SOURCE_ROOT;')
    obj('build:'+path, f'isa = PBXBuildFile; fileRef = {uid("ref:"+path)};')
    refs.append(uid('ref:'+path)); resources.append(uid('build:'+path))
obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Sprechen.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('products',f'isa = PBXGroup; children = ({uid("product")}); name = Products; sourceTree = "<group>";')
obj('rootgroup',f'isa = PBXGroup; children = ({",".join(refs+[uid("products")])}); sourceTree = "<group>";')
obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)}); runOnlyForDeploymentPostprocessing = 0;')
obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resources)}); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for scope in ['project','target']:
    for config in ['Debug','Release']:
        settings = {
            'IPHONEOS_DEPLOYMENT_TARGET':'16.0', 'SDKROOT':'iphoneos', 'SWIFT_VERSION':'5.0',
            'CLANG_ENABLE_MODULES':'YES', 'SWIFT_STRICT_CONCURRENCY':'targeted',
            'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config == 'Debug' else '-O',
            'DEBUG_INFORMATION_FORMAT':'dwarf' if config == 'Debug' else 'dwarf-with-dsym',
        }
        if scope == 'target':
            settings.update({'PRODUCT_BUNDLE_IDENTIFIER':'com.section02.Sprechen','PRODUCT_NAME':'Sprechen','TARGETED_DEVICE_FAMILY':'1','INFOPLIST_FILE':'App/Info.plist','GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_STYLE':'Automatic','OTHER_LDFLAGS':'-lsqlite3','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','ENABLE_PREVIEWS':'YES','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon'})
        if config == 'Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        obj(scope+config, f'isa = XCBuildConfiguration; buildSettings = {{ {" ".join(k+" = "+quoted(v)+";" for k,v in settings.items())} }}; name = {config};')
    obj(scope+'configs',f'isa = XCConfigurationList; buildConfigurations = ({uid(scope+"Debug")},{uid(scope+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")}); buildRules = (); dependencies = (); name = Sprechen; productName = Sprechen; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, de); mainGroup = {uid("rootgroup")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")});')
(root/'Sprechen.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="Sprechen.app" BlueprintName="Sprechen" ReferencedContainer="container:Sprechen.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="Sprechen.app" BlueprintName="Sprechen" ReferencedContainer="container:Sprechen.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="Sprechen.app" BlueprintName="Sprechen" ReferencedContainer="container:Sprechen.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'Sprechen.xcodeproj/xcshareddata/xcschemes/Sprechen.xcscheme').write_text(scheme)
