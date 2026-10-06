floater "fan-menu-v2" {
    ball mainBall: Main {
        size = 56dp
        radius = 28dp
        position = (100dp, 300dp)
        visible = true
        draggable = true
        anchor = topLeft
    }

    ball sub1: Deputy {
        size = 48dp
        radius = 24dp
        position = mainBall.center
        visible = false
        anchor = topLeft
    }

    ball sub2: Deputy {
        size = 48dp
        radius = 24dp
        position = mainBall.center
        visible = false
        anchor = topLeft
    }

    ball sub3: Deputy {
        size = 48dp
        radius = 24dp
        position = mainBall.center
        visible = false
        anchor = topLeft
    }

    ball sub4: Deputy {
        size = 48dp
        radius = 24dp
        position = mainBall.center
        visible = false
        anchor = topLeft
    }

    val expanded: Bool = false

    on mainBall.click {
        if (!expanded) {
            expanded = true
            sub1.visible = true
            sub2.visible = true
            sub3.visible = true
            sub4.visible = true
            val fan = Fan(center: mainBall.center, radius: 140dp, startAngle: 0deg, sweep: 90deg, count: 4)
            await animate [sub1, sub2, sub3, sub4] to fan[].topLeft duration 260ms easing overshoot
        } else {
            expanded = false
            await animate [sub1, sub2, sub3, sub4] to mainBall.center duration 200ms easing decelerate
            sub1.visible = false
            sub2.visible = false
            sub3.visible = false
            sub4.visible = false
        }
    }

    on sub1.click { print("功能 1") }
    on sub2.click { print("功能 2") }
    on sub3.click { print("功能 3") }
    on sub4.click { print("功能 4") }
}
