"""Generate a dependency-free Xcode project using only the Python standard library."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def quote(value): return '"' + str(value).replace('"', '\\"') + '"'
objects = {}
def add(key, body): objects[uid(key)] = body; return uid(key)
def refs(values): return '(' + ', '.join(values) + ',)'

targets = ['ReceiptSplit', 'ReceiptSplitTests', 'ReceiptSplitUITests']
groups, products = [], []
for name in targets:
    files, builds = [], []
    for path in sorted((ROOT / name).glob('*.swift')):
        file = add(str(path.relative_to(ROOT)), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(path.name)}; sourceTree = "<group>";')
        files.append(file)
        builds.append(add('build/' + path.name, f'isa = PBXBuildFile; fileRef = {file};'))
    resource_builds = []
    if name == 'ReceiptSplit':
        asset = add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>";')
        files.append(asset)
        resource_builds.append(add('build/assets', f'isa = PBXBuildFile; fileRef = {asset};'))
        storyboard = add('storyboard', 'isa = PBXFileReference; lastKnownFileType = file.storyboard; path = Main.storyboard; sourceTree = "<group>";')
        files.append(storyboard)
        resource_builds.append(add('build/storyboard', f'isa = PBXBuildFile; fileRef = {storyboard};'))
    groups.append(add('group/' + name, f'isa = PBXGroup; children = {refs(files)}; path = {name}; sourceTree = "<group>";'))
    ext = 'app' if name == 'ReceiptSplit' else 'xctest'
    product = add('product/' + name, f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if ext == "app" else "wrapper.cfbundle"}; includeInIndex = 0; path = {name}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    sources = add('sources/' + name, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(builds)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = add('frameworks/' + name, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    resources = add('resources/' + name, f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(resource_builds) if resource_builds else "()"}; runOnlyForDeploymentPostprocessing = 0;')
    configs = []
    for mode in ['Debug', 'Release']:
        settings = {
            'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.ioslab.Storyboard.' + name,
            'GENERATE_INFOPLIST_FILE': 'YES', 'SWIFT_VERSION': '5.0', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0',
            'SDKROOT': 'iphoneos', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
            'TARGETED_DEVICE_FAMILY': '1,2', 'CODE_SIGN_STYLE': 'Automatic', 'CURRENT_PROJECT_VERSION': '1',
            'MARKETING_VERSION': '1.0', 'SWIFT_EMIT_LOC_STRINGS': 'YES',
            'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
        }
        if name == 'ReceiptSplit':
            settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
            settings.update({'INFOPLIST_KEY_NSCameraUsageDescription': 'Scan a receipt to recognize its text privately on your device.', 'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES', 'INFOPLIST_KEY_CFBundleDisplayName': 'ReceiptSplit', 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone': 'UIInterfaceOrientationPortrait', 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad': 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'})
        elif name == 'ReceiptSplitTests':
            settings.update({'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/ReceiptSplit.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ReceiptSplit', 'BUNDLE_LOADER': '$(TEST_HOST)'})
        else: settings['TEST_TARGET_NAME'] = 'ReceiptSplit'
        configs.append(add('config/' + name + mode, 'isa = XCBuildConfiguration; buildSettings = {' + ''.join(f'{k} = {quote(v)};' for k, v in settings.items()) + f'}}; name = {mode};'))
    configs_id = add('configs/' + name, f'isa = XCConfigurationList; buildConfigurations = {refs(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    dependencies = []
    if name != 'ReceiptSplit':
        proxy = add('proxy/' + name, f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target/ReceiptSplit")}; remoteInfo = ReceiptSplit;')
        dependencies.append(add('dependency/' + name, f'isa = PBXTargetDependency; target = {uid("target/ReceiptSplit")}; targetProxy = {proxy};'))
    product_type = 'application' if name == 'ReceiptSplit' else 'bundle.unit-test' if name == 'ReceiptSplitTests' else 'bundle.ui-testing'
    add('target/' + name, f'isa = PBXNativeTarget; buildConfigurationList = {configs_id}; buildPhases = {refs([sources, frameworks, resources])}; buildRules = (); dependencies = {refs(dependencies) if dependencies else "()"}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{product_type}";')

product_group = add('products', f'isa = PBXGroup; children = {refs(products)}; name = Products; sourceTree = "<group>";')
root_group = add('root', f'isa = PBXGroup; children = {refs(groups + [product_group])}; sourceTree = "<group>";')
configs = []
for mode in ['Debug', 'Release']:
    configs.append(add('projectconfig/' + mode, f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; ENABLE_TESTABILITY = {"YES" if mode == "Debug" else "NO"}; DEBUG_INFORMATION_FORMAT = {quote("dwarf" if mode == "Debug" else "dwarf-with-dsym")}; }}; name = {mode};'))
config_list = add('projectconfigs', f'isa = XCConfigurationList; buildConfigurations = {refs(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }}; buildConfigurationList = {config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {root_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {refs([uid("target/" + n) for n in targets])};')
output = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
output += '\n'.join(f'{key} = {{ {body} }};' for key, body in objects.items())
output += f'\n}}; rootObject = {uid("project")}; }}\n'
(ROOT / 'ReceiptSplit.xcodeproj/project.pbxproj').write_text(output)
def buildable(name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target/" + name)}" BuildableName="{name}.{"app" if name == "ReceiptSplit" else "xctest"}" BlueprintName="{name}" ReferencedContainer="container:ReceiptSplit.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable('ReceiptSplit')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{''.join('<TestableReference skipped="NO">' + buildable(n) + '</TestableReference>' for n in targets[1:])}</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('ReceiptSplit')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('ReceiptSplit')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(ROOT / 'ReceiptSplit.xcodeproj/xcshareddata/xcschemes/ReceiptSplit.xcscheme').write_text(scheme)
print('Generated ReceiptSplit.xcodeproj')
