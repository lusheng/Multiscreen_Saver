#!/usr/bin/env python3
"""Generate the tiny dependency-free G1 Xcode project deterministically."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent
files = ['Diagnostics.swift', 'Configuration.swift', 'DiagnosticSaverView.swift']
objects = []
def add(key, value): objects.append(f'{key} = {{ {value} }};')
for i, name in enumerate(files):
    add(f'F{i}', f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>";')
    add(f'B{i}', f'isa = PBXBuildFile; fileRef = F{i};')
add('ROOT', 'isa = PBXProject; buildConfigurationList = PCL; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; mainGroup = GROUP; productRefGroup = PRODUCTS; projectDirPath = ""; targets = (TARGET);')
add('GROUP', 'isa = PBXGroup; children = (SOURCES, PRODUCTS); sourceTree = "<group>";')
add('SOURCES', 'isa = PBXGroup; path = Sources; children = (F0, F1, F2); sourceTree = "<group>";')
add('PRODUCTS', 'isa = PBXGroup; children = (PRODUCT); name = Products; sourceTree = "<group>";')
add('PRODUCT', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = MultiscreenSaver.saver; sourceTree = BUILT_PRODUCTS_DIR;')
add('TARGET', 'isa = PBXNativeTarget; name = MultiscreenSaver; buildConfigurationList = TCL; buildPhases = (SBUILD); buildRules = (); dependencies = (); productName = MultiscreenSaver; productReference = PRODUCT; productType = "com.apple.product-type.bundle";')
add('SBUILD', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (B0, B1, B2); runOnlyForDeploymentPostprocessing = 0;')
for prefix in ['P', 'T']:
    add(prefix+'CL', f'isa = XCConfigurationList; buildConfigurations = ({prefix}DEBUG, {prefix}RELEASE); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
    for config in ['Debug', 'Release']:
        settings = 'ALWAYS_SEARCH_USER_PATHS = NO; SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 27.0; ARCHS = arm64; SWIFT_VERSION = 5.0;'
        if prefix == 'T':
            settings += ' PRODUCT_NAME = MultiscreenSaver; PRODUCT_BUNDLE_IDENTIFIER = com.lusheng.MultiscreenSaver; WRAPPER_EXTENSION = saver; INFOPLIST_FILE = Sources/Info.plist; GENERATE_INFOPLIST_FILE = NO; CURRENT_PROJECT_VERSION = 6; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; COMBINE_HIDPI_IMAGES = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone";'
        add(prefix+config.upper(), f'isa = XCBuildConfiguration; name = {config}; buildSettings = {{ {settings} }};')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = ROOT; }\n'
(root/'MultiscreenSaver.xcodeproj/project.pbxproj').write_text(text)
