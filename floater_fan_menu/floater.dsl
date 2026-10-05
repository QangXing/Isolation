// 扇形展开编程球
// 单击主球时，4 个功能副球以主球为圆心呈 90° 扇形展开；
// 再次单击收回。展开方向会根据主球所在屏幕象限自动调整，
// 始终朝向屏幕中心展开，避免副球超出屏幕。

// 全局状态：0=收起，1=展开
expanded = 0

ball(main, "mainBall") {
    size(56)
    cornerRadius(28)
    location("mainBall", 100, 300)
    status(show, "mainBall")

    singleClick {
        // 当前主球左上角与中心点
        mainX = found("mainBall", x)
        mainY = found("mainBall", y)
        mainCx = mainX + 28
        mainCy = mainY + 28

        if (expanded == 1) {
            // 收起：所有副球回到主球中心后隐藏
            animate("sub1", "x", mainX, 200, "decelerate")
            animate("sub1", "y", mainY, 200, "decelerate")
            animate("sub2", "x", mainX, 200, "decelerate")
            animate("sub2", "y", mainY, 200, "decelerate")
            animate("sub3", "x", mainX, 200, "decelerate")
            animate("sub3", "y", mainY, 200, "decelerate")
            animate("sub4", "x", mainX, 200, "decelerate")
            animate("sub4", "y", mainY, 200, "decelerate")

            wait(200)
            status(hide, "sub1")
            status(hide, "sub2")
            status(hide, "sub3")
            status(hide, "sub4")
            expanded = 0
        } else {
            // 根据主球所在屏幕象限，决定扇形展开方向
            centerX = screen("centerX")
            centerY = screen("centerY")

            if (mainCx > centerX) {
                dirX = -1
            } else {
                dirX = 1
            }
            if (mainCy > centerY) {
                dirY = -1
            } else {
                dirY = 1
            }
            if (dirX < 0) {
                startAngle = 180
            } else {
                startAngle = 0
            }
            if (dirY < 0) {
                sweep = -90
            } else {
                sweep = 90
            }

            PI = 3.14159265
            radius = 140
            subSize = 48

            // 副球 1：扇形起点
            t1 = 0.0
            angle1 = startAngle + sweep * t1
            rad1 = angle1 * PI / 180.0
            tcx1 = mainCx + radius * cos(rad1)
            tcy1 = mainCy + radius * sin(rad1)
            tx1 = tcx1 - subSize / 2
            ty1 = tcy1 - subSize / 2

            // 副球 2
            t2 = 0.333333
            angle2 = startAngle + sweep * t2
            rad2 = angle2 * PI / 180.0
            tcx2 = mainCx + radius * cos(rad2)
            tcy2 = mainCy + radius * sin(rad2)
            tx2 = tcx2 - subSize / 2
            ty2 = tcy2 - subSize / 2

            // 副球 3
            t3 = 0.666666
            angle3 = startAngle + sweep * t3
            rad3 = angle3 * PI / 180.0
            tcx3 = mainCx + radius * cos(rad3)
            tcy3 = mainCy + radius * sin(rad3)
            tx3 = tcx3 - subSize / 2
            ty3 = tcy3 - subSize / 2

            // 副球 4：扇形终点
            t4 = 1.0
            angle4 = startAngle + sweep * t4
            rad4 = angle4 * PI / 180.0
            tcx4 = mainCx + radius * cos(rad4)
            tcy4 = mainCy + radius * sin(rad4)
            tx4 = tcx4 - subSize / 2
            ty4 = tcy4 - subSize / 2

            // 先把副球叠到主球位置，再显示，再动画展开
            location("sub1", mainX, mainY)
            location("sub2", mainX, mainY)
            location("sub3", mainX, mainY)
            location("sub4", mainX, mainY)

            status(show, "sub1")
            status(show, "sub2")
            status(show, "sub3")
            status(show, "sub4")

            pulse("mainBall", 1.08, 150)

            animate("sub1", "x", tx1, 260, "overshoot")
            animate("sub1", "y", ty1, 260, "overshoot")
            animate("sub2", "x", tx2, 260, "overshoot")
            animate("sub2", "y", ty2, 260, "overshoot")
            animate("sub3", "x", tx3, 260, "overshoot")
            animate("sub3", "y", ty3, 260, "overshoot")
            animate("sub4", "x", tx4, 260, "overshoot")
            animate("sub4", "y", ty4, 260, "overshoot")

            expanded = 1
        }
    }
}

// 4 个功能副球，默认隐藏
ball(deputy, "sub1") {
    size(48)
    cornerRadius(24)
    status(hide, "sub1")
    singleClick { print("功能 1") }
}

ball(deputy, "sub2") {
    size(48)
    cornerRadius(24)
    status(hide, "sub2")
    singleClick { print("功能 2") }
}

ball(deputy, "sub3") {
    size(48)
    cornerRadius(24)
    status(hide, "sub3")
    singleClick { print("功能 3") }
}

ball(deputy, "sub4") {
    size(48)
    cornerRadius(24)
    status(hide, "sub4")
    singleClick { print("功能 4") }
}
