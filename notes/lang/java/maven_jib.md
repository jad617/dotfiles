Here’s a bite-sized guide to getting Jib up and running in your Maven (pom.xml) build so you can produce Docker/OCI images without a Dockerfile.

---

## 1. Add the Jib plugin

In your `<project><build><plugins>` section, declare:

```xml
<plugin>
  <groupId>com.google.cloud.tools</groupId>
  <artifactId>jib-maven-plugin</artifactId>
  <version>3.4.1</version>  <!-- use the latest stable version -->
  <configuration>
    <!-- we'll fill this in below -->
  </configuration>
</plugin>
```

---

## 2. Basic “to” configuration

Tell Jib where to push (or tag) the image:

```xml
<configuration>
  <to>
    <image>gcr.io/my-project/my-app:${project.version}</image>
    <!-- or "docker://my-app:${project.version}" to push into local Docker daemon -->
  </to>
</configuration>
```

---

## 3. Credentials

If you’re publishing to a private registry, supply credentials:

```xml
<configuration>
  <to>
    <image>registry.example.com/my-org/my-app</image>
    <auth>
      <username>${env.REGISTRY_USER}</username>
      <password>${env.REGISTRY_PASSWORD}</password>
    </auth>
  </to>
</configuration>
```

> **Tip:** It’s best to pick up credentials from your CI/CD secrets or environment.

---

## 4. Container settings

Customize how your app is packaged:

```xml
<configuration>
  <container>
    <!-- what port your app listens on -->
    <ports>
      <port>8080</port>
    </ports>
    <!-- JVM flags for a Java app -->
    <jvmFlags>
      <jvmFlag>-Xms512m</jvmFlag>
      <jvmFlag>-Xmx1g</jvmFlag>
    </jvmFlags>
    <!-- environment variables inside the container -->
    <environment>
      <SPRING_PROFILES_ACTIVE>prod</SPRING_PROFILES_ACTIVE>
    </environment>
    <!-- avoid “reproducible builds” timestamping issues -->
    <creationTime>USE_CURRENT_TIMESTAMP</creationTime>
  </container>
</configuration>
```

---

## 5. Build goals

* **To your Docker daemon**:

  ```bash
  mvn compile jib:dockerBuild
  ```

* **Directly to registry**:

  ```bash
  mvn compile jib:build
  ```

No `docker build`, no local Dockerfile—Jib layers your app intelligently (libs vs resources vs classes) for fast rebuilds.

---

## 6. Full example snippet

```xml
<build>
  <plugins>
    <plugin>
      <groupId>com.google.cloud.tools</groupId>
      <artifactId>jib-maven-plugin</artifactId>
      <version>3.4.1</version>
      <configuration>
        <from>
          <image>eclipse-temurin:17-jre</image>
        </from>
        <to>
          <image>registry.example.com/my-org/my-app:${project.version}</image>
          <auth>
            <username>${env.REGISTRY_USER}</username>
            <password>${env.REGISTRY_PASSWORD}</password>
          </auth>
        </to>
        <container>
          <ports>
            <port>8080</port>
          </ports>
          <environment>
            <SPRING_PROFILES_ACTIVE>prod</SPRING_PROFILES_ACTIVE>
          </environment>
          <jvmFlags>
            <jvmFlag>-Xms512m</jvmFlag>
            <jvmFlag>-Xmx1g</jvmFlag>
          </jvmFlags>
          <creationTime>USE_CURRENT_TIMESTAMP</creationTime>
        </container>
      </configuration>
    </plugin>
  </plugins>
</build>
```

---

## 7. A few extra tweaks

* **Skip tests**:

  ```bash
  mvn -DskipTests compile jib:build
  ```

* **Custom layers** (e.g. include extra files):

  ```xml
  <extraDirectories>
    <paths>
      <path>
        <from>${project.basedir}/src/main/jib</from>
        <into>/app/config</into>
      </path>
    </paths>
  </extraDirectories>
  ```

* **Advanced Auth**: Jib also supports OAuth (GCR, ECR), Docker credential helpers, or your `~/.docker/config.json`.

---

With this in place you get:

* **Automatic layering** for super-fast incremental rebuilds
* **No Dockerfile** clutter
* **Consistent, reproducible** images

Give it a spin!
