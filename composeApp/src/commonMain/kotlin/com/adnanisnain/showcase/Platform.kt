package com.adnanisnain.showcase

interface Platform {
    val name: String
}

expect fun getPlatform(): Platform