import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/commands/umoci.dart';

import 'tiefile.dart';
import '../util.dart';
import '../extensions.dart';

class Config {
  String target = '';
  String baseDir = '';
  String files = '';
  String filesCommitPrefix = 'file|files';
  String apps = '';
  String appsCommitPrefix = 'app|apps|run|update';
  String filePrefix = "tie";
  bool appNamesRequired = false;
  bool ignoreErrors = false;
  bool verbose = false;
  bool traceGenerated = false;
  bool traceCommands = false;
  bool traceTieFile = false;
  String secretLabels = 'pass|secret|token|key|cert';
  Set<String> secretLabelSet = {};
  bool banner = true;
  bool createNamespaces = true;
  String scratchDir = ".tiecd";
}


class TieError implements Exception {
  String cause;
  TieError(this.cause);
}


class TieContext {
  Config config;
  List<ImageRepository> repositories;
  App app;

  TieContext(this.config, this.repositories, this.app);

  Map<String, String> getEnv() {
    // build properties
    var properties = <String, String>{};
    // set process env first
    Map<String, String> envVars = Platform.environment;
    envVars.forEach((key, value) => properties[key] = value);

    if (app.deploy != null) {
      if (app.deploy!.envPropertyFiles != null &&
          app.deploy!.envPropertyFiles!.isNotEmpty) {
        for (var envFile in app.deploy!.envPropertyFiles!) {
          readProperties(config, envFile, properties);
        }
      }
      if (app.deploy!.env != null && app.deploy!.env!.isNotEmpty) {
        app.deploy!.env!.forEach((key, value) => properties[key] = value);
      }
    }

    // deploy env takes highest order
    if (app.tiecdEnvPropertyFiles != null &&
        app.tiecdEnvPropertyFiles!.isNotEmpty) {
      for (var deployFile in app.tiecdEnvPropertyFiles!) {
        readProperties(config, deployFile, properties);
      }
    }

    if (app.tiecdEnv != null && app.tiecdEnv!.isNotEmpty) {
      app.tiecdEnv!.forEach((key, value) => properties[key] = value);
    }

    //properties.forEach((k,v) => print('${k}: ${v}'));
    return properties;
  }
}

class DeployContext extends TieContext {

  DeployHandler handler;
  Environment environment;

  DeployContext(super.config, super.repositories, this.handler, this.environment, super.app);

}

class BuildContext extends TieContext {

  BuildContext(super.config, super.repositories, super.app);

}

void readProperties(Config config, String fileName, Map<String,String> properties) {
  if (File('${config.baseDir}/$fileName').existsSync()) {
    var value = File('${config.baseDir}/$fileName').readAsStringSync();
    LineSplitter splitter = LineSplitter();
    List<String> lines = splitter.convert(value);
    for(var line in lines) {
      var expanded = varExpandByLine(line, ".properties");
      var parts = split(expanded, "=", max: 2);
      if (parts.length == 2) {
        properties[parts[0]] = parts[1];
      } else if (parts.length == 1) {
        properties[parts[0]] = "\"\"";
      }
    }
  } else {
    throw TieError('property file file does not exist: $fileName');
  }
}


abstract class DeployHandler {
  void expandEnvironment(Environment environment);
  Future<void> login(DeployContext deployContext);
  Future<void> logoff(DeployContext deployContext);
  Future<void> handleImage(DeployContext deployContext);
  Future<void> handleConfig(DeployContext deployContext);
  Future<void> handleSecrets(DeployContext deployContext);
  Future<void> handleHelm(DeployContext deployContext);
  Future<String> deploy(DeployContext deployContext);
  Future<void> runScripts(DeployContext deployContext, List<String> scripts);
  Future<void> removeHelm(DeployContext deployContext);
  Map<String,String> getHandlerEnv();
  String getDestinationRegistry(Environment environment);
  String getDestinationImageName(Environment environment, Image image);
}


enum CIProvider { gitlab, github, unknown }

abstract class ProjectProvider {
  BuildType? buildType;
  ImageType? imageType;
  String? name;
  String? version;
  CIProvider? ciProvider;


  ProjectProvider() {
    var test = Platform.environment['CI_PROJECT_NAME'];
    if (test.isNotNullNorEmpty) {
      ciProvider = CIProvider.gitlab;
    } else {
      test = Platform.environment['GITHUB_REPOSITORY'];
      if (test.isNotNullNorEmpty) {
        ciProvider = CIProvider.github;
      }
    }
    ciProvider ??= CIProvider.unknown;
  }

  void init();
  bool isProject();

  // image path of the container registry for this project
  // if the ci environment provides one
  String? imagePath() {
    if (ciProvider == CIProvider.gitlab) {
      return Platform.environment['CI_REGISTRY_IMAGE'];
    } else if (ciProvider == CIProvider.gitlab) {
      if (Platform.environment['GITHUB_REPOSITORY'].isNotNullNorEmpty) {
        return 'ghcr.io/${Platform.environment['GITHUB_REPOSITORY']}';
      }
    }
    return null;
  }

  List<String>? beforeBuildScripts();
  List<String>? buildScripts();
  List<String>? afterBuildScripts();
  Map<String,String> buildEnv();

}
