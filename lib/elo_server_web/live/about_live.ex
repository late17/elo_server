defmodule EloServerWeb.AboutLive do
  use EloServerWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="rating-page">
      <div class="rating-wrapper">
        <header class="rating-header">
          <h1>RATING DEBATES UA</h1>
        </header>

        <main class="rating-main">
          <div class="rating-table-container rating-add-padding-about">
            <p><b>Debate Elo System (DES)</b></p>
            <p><b>Організаційні питання:</b></p>

            <p>
              Данні беруться з Кішки на домені:
              <a href="https://tab.uadebate.com/" target="_blank">https://tab.uadebate.com/</a>
            </p>

            <p>
              До уваги беруться лише турніри з класичними правилами, Fight Club або Ferum cup поза кейсом.
            </p>

            <p>
              До теберів та організаторів. Прошу завжди формувати теб з справжніх імен. Для цього робити реєстрацію де учасники окремо вказують прізвище імʼя.
              Технічні команди називати відповідним чином (тех людина, гравець 1 etc.)
              Також будь ласка заповнюйте все, пів фінали, фінали і т.д.
            </p>

            <p>
              В турнірах є тех команди - вони ніяк не впливають на elo.
            </p>

            <p><b>Правила відображення в списку:</b></p>

            <p>
              Відображаються гравці що зіграли більше 20 ігор за всю історію та ХОЧА б одну гру за попередній рік.
            </p>

            <p><b>Elo математика:</b></p>

            <p>
              В цілому все було взято звідси:
              <a
                href="https://monashdebaters.com/introducing-elo-ratings-in-british-parliamentary-debating/"
                target="_blank"
              >
                https://monashdebaters.com/introducing-elo-ratings-in-british-parliamentary-debating
              </a>
            </p>

            <p>
              Якщо коротко, все працює як в шахах.
            </p>

            <p>
              <b class="sub">Ситуація 1:</b>
              <br /> Гравець A 1500, Гравець B 1500<br />
              У випадку перемоги будь кого з них, одному з них віднімається умовні 20 поінтів а іншому добавляється.
            </p>

            <p>
              <b class="sub">Ситуація 2:</b><br />
              Гравець A 1600, Гравець B 2000<br />
              У цьому випадку очікується що гравець B має в 10 разів більше шансів перемогти.<br />
              Якщо він виграє — отримує умовно +2, A -2.<br /> Якщо A виграє — отримує +40, B -40.
            </p>

            <p>
              <b class="sub">Чому кількість поінтів умовна? Існує K-factor — коефіцієнт зміни elo.</b>
            </p>

            <p>
              На початку кількість поінтів що віднімаються або додаються велика (+400, -150 і т.д.), бо K-factor великий.
              Це потрібно для калібрування (перші 8–10 ігор).
            </p>

            <p>
              Для відкаліброваних гравців K-factor також відрізняється в залежності від рейтингу:
            </p>

            <p>
              - Низький elo → більший K-factor<br /> - Високий elo → менший K-factor
            </p>

            <p>
              Чому це зроблено? Вважається що гравці з низьким elo більш нестабільні, можуть швидко зрости у своїй грі і відповідно швидше піднімуть elo. Гравці з високим elo вже (мабуть) навчилися грати в дебати і грають більш стабільно.
            </p>
          </div>
        </main>

        <footer class="rating-footer">
          © {Date.utc_today().year} Lviv Debate Union спільно з Аніме на Аві, Східняцьке Бидло Продакшн та КООП "Озеро"
          | <.link navigate={~p"/"}>Rating</.link>
        </footer>
      </div>
    </div>
    """
  end
end
