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
        visible = false
        anchor = topLeft
    }

    ball sub2: Deputy {
        size = 48dp
        radius = 24dp
        visible = false
        anchor = topLeft
    }

    ball sub3: Deputy {
        size = 48dp
        radius = 24dp
        visible = false
        anchor = topLeft
    }

    ball sub4: Deputy {
        size = 48dp
        radius = 24dp
        visible = false
        anchor = topLeft
    }

    on mainBall.click {
        print(mainBall.center)
    }

    on sub1.click { print("功能 1") }
    on sub2.click { print("功能 2") }
    on sub3.click { print("功能 3") }
    on sub4.click { print("功能 4") }
}
