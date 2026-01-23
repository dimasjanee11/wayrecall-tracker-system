lazy val root = project
  .in(file("."))
  .aggregate(
    connectionManager,
    historyWriter,
    deviceManager
  )
  .settings(
    name := "wayrecall-tracker-system",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Connection Manager - приём GPS данных
lazy val connectionManager = project
  .in(file("services/connection-manager"))
  .settings(
    name := "connection-manager",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// History Writer - сохранение в TimescaleDB
lazy val historyWriter = project
  .in(file("services/history-writer"))
  .settings(
    name := "history-writer",
    version := "0.1.0",
    scalaVersion := "3.4.0",
    libraryDependencies ++= Seq(
      "dev.zio" %% "zio" % "2.0.20",
      "dev.zio" %% "zio-kafka" % "2.2.0",
      "org.postgresql" % "postgresql" % "42.7.1",
      "com.zaxxer" % "HikariCP" % "5.1.0"
    )
  )
  .dependsOn(connectionManager % "test->test;compile->compile")

// Device Manager - управление командами и трекерами
lazy val deviceManager = project
  .in(file("services/device-manager"))
  .settings(
    name := "device-manager",
    version := "0.1.0",
    scalaVersion := "3.4.0",
    libraryDependencies ++= Seq(
      "dev.zio" %% "zio" % "2.0.20",
      "dev.zio" %% "zio-redis" % "0.2.0",
      "org.apache.kafka" % "kafka-clients" % "3.6.1"
    )
  )
  .dependsOn(connectionManager % "test->test;compile->compile")

// Общие настройки
inThisBuild(Seq(
  organization := "com.wayrecall",
  scalacOptions ++= Seq(
    "-encoding", "utf8",
    "-deprecation",
    "-unchecked",
    "-language:postfixOps",
    "-feature"
  ),
  resolvers ++= Seq(
    "Maven Central" at "https://repo1.maven.org/maven2/",
    Resolver.sonatypeRepo("releases")
  )
))
