fn main() {
    // sqlx::migrate! embeds files; adding a migration must invalidate the build.
    println!("cargo:rerun-if-changed=migrations");
}
