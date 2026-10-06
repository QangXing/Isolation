floater "fan-menu-v2" {
    ball mainBall: Main {
        size = 56dp
        radius = 28dp
        position = (100dp, 300dp)
        visible = true
        draggable = true
        anchor = topLeft
    }

    ball sub1..4: Deputy {
        size = 48dp
        radius = 24dp
        position = mainBall.center
        visible = false
        anchor = topLeft
    }

    state collapsed {
        sub1..4.visible = false
    }

    state expanded {
        let fan: Fan = Fan(center: mainBall.center, radius: 140dp, startAngle: 0deg, sweep: 90deg, count: 4)
        sub1..4.visible = true
        await animate [sub1..4] to fan[].topLeft duration 260ms easing overshoot
    }

    transition collapsed -> expanded on mainBall.click
    transition expanded -> collapsed on mainBall.click

    on sub1.click { print("功能 1") }
    on sub2.click { print("功能 2") }
    on sub3.click { print("功能 3") }
    on sub4.click { print("功能 4") }
}
